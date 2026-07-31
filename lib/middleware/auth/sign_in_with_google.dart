import 'package:codraw/actions/auth/sign_in_with_google_action.dart';
import 'package:codraw/actions/auth/store_auth_step_action.dart';
import 'package:codraw/actions/auth/store_auth_user_data_action.dart';
import 'package:codraw/enums/auth/auth_step_enum.dart';
import 'package:codraw/extensions/redux/store_extensions.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:codraw/services/auth_service.dart';
import 'package:redux/redux.dart';

class SignInWithGoogleMiddleware
    extends TypedMiddleware<AppState, SignInWithGoogleAction> {
  SignInWithGoogleMiddleware(AuthService authService)
      : super((store, action, next) async {
          next(action);

          try {
            store.dispatch(
                StoreAuthStepAction(step: AuthStepEnum.contactingGoogle));

            // signInWithGoogle runs the full flow (web popup or native
            // credential exchange) and returns null if the user aborted.
            final authUserData = await authService.signInWithGoogle();

            // If user cancelled sign in, reset UI and return
            if (authUserData == null) {
              store.dispatch(
                  StoreAuthStepAction(step: AuthStepEnum.waitingForInput));
              return;
            }

            // The authStateChanges stream also emits this AuthUserData and we
            // are already listening to that stream to update app state.
            store.dispatch(StoreAuthUserDataAction(authUserData: authUserData));
            store.dispatch(
                StoreAuthStepAction(step: AuthStepEnum.waitingForInput));
          } catch (error, trace) {
            store.dispatchProblem(error, trace);
          }
        });
}
