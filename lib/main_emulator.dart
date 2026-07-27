import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'actions/auth/store_auth_user_data_action.dart';
import 'actions/redux_action.dart';
import 'firebase_options.dart';
import 'models/auth/auth_provider_data.dart';
import 'models/auth/auth_user_data.dart';
import 'services/auth_service.dart';
import 'utils/redux_bundle.dart';
import 'widgets/app-init/app_widget.dart';

/// Local-demo entrypoint: runs the canvas against a local Firestore emulator so
/// an agent peer (`tool/agent_draw.dart`) can draw boxes onto it — no cloud, no
/// cost, no OAuth.
///
/// Auth is faked (see [_FakeAuthService]) rather than run through the Firebase
/// Auth emulator, because in this environment `firebase emulators:start`'s port
/// pre-check is broken, so we run the Firestore emulator JAR directly and have
/// no Auth emulator to sign into. Seeding a user is all the UI gate
/// (`InitialPage`) needs to show the drawing canvas.
///
/// Launch (with the Firestore JAR already listening on 127.0.0.1:8080):
///   flutter run -d web-server --web-port 5001 -t lib/main_emulator.dart
///
/// Kept a SEPARATE entrypoint so production main.dart stays untouched.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Point Firestore at the local emulator BEFORE anything reads it.
  FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);

  runApp(AppWidget(
    redux: ReduxBundle(authService: _FakeAuthService()),
  ));
}

/// Feeds the store a signed-in [AuthUserData] the instant the app asks the auth
/// service to connect — no Firebase Auth involved. Everything downstream (the
/// canvas, the Firestore listener) runs exactly as in production.
class _FakeAuthService extends AuthService {
  _FakeAuthService() : super();

  static final _demoUser = AuthUserData(
    uid: 'demo-user',
    displayName: 'Demo',
    isAnonymous: true,
    emailVerified: false,
    providers: <AuthProviderData>[].lock,
  );

  /// `Stream.multi` emits the fake sign-in to EACH subscriber the moment it
  /// listens — so delivery depends on neither event-vs-subscribe ordering (a
  /// broadcast controller would drop an add that precedes the listener) nor
  /// single-subscription (which would crash a hot-restart re-listen). Robust to
  /// both; the stream self-emits, so [connectAuthStateToStore] is a no-op.
  @override
  Stream<ReduxAction> get storeStream => Stream.multi((controller) {
        controller.add(StoreAuthUserDataAction(authUserData: _demoUser));
        controller.close();
      });

  @override
  void connectAuthStateToStore() {}
}
