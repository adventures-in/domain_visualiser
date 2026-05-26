import 'dart:async';

import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/extensions/firebase/firebase_auth_extensions.dart';
import 'package:domain_visualiser/extensions/redux/actions_stream_controller_extensions.dart';
import 'package:domain_visualiser/models/auth/apple_id_credential.dart';
import 'package:domain_visualiser/models/auth/auth_user_data.dart';
import 'package:domain_visualiser/models/auth/google_sign_in_credential.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService {
  final FirebaseAuth _firebaseAuth;

  /// [StreamController] for adding auth state actions
  final StreamController<ReduxAction> _eventsController;

  /// The [Stream] is used just once on app load, to
  /// connect the [Database] to the redux [Store]

  Stream<ReduxAction> get storeStream => _eventsController.stream;

  /// We keep a subscription to the firebase auth state stream so we can
  /// disconnect at a later time.
  StreamSubscription<User?>? _firebaseAuthStateSubscription;

  AuthService(
      {FirebaseAuth? auth, StreamController<ReduxAction>? eventsController})
      : _firebaseAuth = auth ?? FirebaseAuth.instance,
        _eventsController = eventsController ?? StreamController<ReduxAction>();

  void connectAuthStateToStore() {
    try {
      // connect the firebase auth state to the store and keep the subscription
      _firebaseAuthStateSubscription?.cancel();
      _firebaseAuthStateSubscription =
          _firebaseAuth.reactToAuthStateChangesWith(_eventsController);
    } catch (error, trace) {
      _eventsController.addProblem(error, trace);
    }
  }

  Future<String?> getCurrentUserId() async {
    final user = _firebaseAuth.currentUser;
    return user?.uid;
  }

  void disconnectAuthState() {
    _firebaseAuthStateSubscription?.cancel();
  }

  /// google_sign_in 7.x replaced the constructor with a singleton that must be
  /// initialized once before use. Guarded so repeated sign-in attempts don't
  /// re-initialize.
  bool _googleSignInInitialized = false;

  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    await GoogleSignIn.instance.initialize();
    _googleSignInInitialized = true;
  }

  /// `null` in case where sign in process was aborted.
  ///
  /// google_sign_in 7.x: `signIn()` -> `authenticate()` (throws on cancel
  /// rather than returning null), and the authentication result now carries
  /// only an `idToken`. The OAuth access token, when needed, comes from the
  /// separate authorization client. Firebase sign-in only requires the
  /// idToken, so the access token is best-effort.
  Future<GoogleSignInCredential?> getGoogleCredential() async {
    await _ensureGoogleSignInInitialized();

    try {
      final account =
          await GoogleSignIn.instance.authenticate(scopeHint: ['email']);
      final authorization =
          await account.authorizationClient.authorizationForScopes(['email']);

      return GoogleSignInCredential(
        idToken: account.authentication.idToken,
        accessToken: authorization?.accessToken,
      );
    } on GoogleSignInException catch (e) {
      // user aborted the flow
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  /// Signs in with Google and returns the user, or `null` if the user aborted.
  ///
  /// Platform split: google_sign_in 7.x has no programmatic `authenticate()`
  /// on web, so there we use Firebase's own popup flow
  /// (`signInWithPopup(GoogleAuthProvider)`), which handles the OAuth dance and
  /// Firebase sign-in in one step. On native we exchange a google_sign_in
  /// credential via `signInWithCredential`.
  Future<AuthUserData?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()..addScope('email');
        final userCredential = await _firebaseAuth.signInWithPopup(provider);
        return userCredential.user?.toModel();
      }

      final credential = await getGoogleCredential();
      if (credential == null) return null; // user aborted

      final authCredential = GoogleAuthProvider.credential(
        accessToken: credential.accessToken,
        idToken: credential.idToken,
      );
      final userCredential =
          await _firebaseAuth.signInWithCredential(authCredential);
      return userCredential.user?.toModel();
    } on FirebaseAuthException catch (e) {
      // user dismissed the web popup — treat as a cancel, not an error
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request' ||
          e.code == 'web-context-canceled') {
        return null;
      }
      rethrow;
    }
  }

  Future<AppleIdCredential> getAppleCredential() async {
    final appleIdCredential =
        await SignInWithApple.getAppleIDCredential(scopes: [
      AppleIDAuthorizationScopes.email,
      AppleIDAuthorizationScopes.fullName,
    ]);

    return appleIdCredential.toModel();
  }

  Future<AuthUserData> signInWithApple(
      {required AppleIdCredential credential}) async {
    // convert to OAuthCredential
    final oAuthCredential = OAuthProvider('apple.com').credential(
      idToken: credential.identityToken,
      accessToken: credential.authorizationCode,
    );

    // use the credential to sign in to firebase
    final userCredential =
        await FirebaseAuth.instance.signInWithCredential(oAuthCredential);
    // not sure why user would be null (docs don't say) so we throw if it is
    final user = userCredential.user!;
    return user.toModel();
  }

  /// The stream of auth state is connected to the store so the app state will
  /// be automatically updated
  Future<void> signOut() async {
    await _ensureGoogleSignInInitialized();
    await GoogleSignIn.instance.signOut();
    await _firebaseAuth.signOut();
  }
}
