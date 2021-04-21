import 'package:domain_visualiser/actions/auth/sign_in_with_google_action.dart';
import 'package:domain_visualiser/actions/auth/store_auth_step_action.dart';
import 'package:domain_visualiser/actions/auth/store_auth_user_data_action.dart';
import 'package:domain_visualiser/enums/auth/auth_step_enum.dart';
import 'package:domain_visualiser/extensions/redux/store_extensions.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/services/auth_service.dart';
import 'package:redux/redux.dart';

class SignInWithGoogleMiddleware
    extends TypedMiddleware<AppState, SignInWithGoogleAction> {
  SignInWithGoogleMiddleware(AuthService authService)
      : super((store, action, next) async {
          next(action);

          try {
            store.dispatch(
                StoreAuthStepAction(step: AuthStepEnum.contactingGoogle));

            final credential = await authService.getGoogleCredential();

            // If user cancelled sign in, reset UI and return
            if (credential == null) {
              store.dispatch(
                  StoreAuthStepAction(step: AuthStepEnum.waitingForInput));
              return;
            }

            store.dispatch(
                StoreAuthStepAction(step: AuthStepEnum.signingInWithFirebase));

            // The authStateChanges stream will emit the same AuthUserData and
            // we are already listening to that stream and updating the app state
            // with whatever gets emitted.
            final authUserData =
                await authService.signInWithGoogle(credential: credential);

            store.dispatch(StoreAuthUserDataAction(authUserData: authUserData));
            store.dispatch(
                StoreAuthStepAction(step: AuthStepEnum.waitingForInput));
          } catch (error, trace) {
            store.dispatchProblem(error, trace);
          }
        });
}
