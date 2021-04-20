import 'package:domain_visualiser/actions/auth/sign_in_with_apple_action.dart';
import 'package:domain_visualiser/actions/auth/store_auth_step_action.dart';
import 'package:domain_visualiser/actions/auth/store_auth_user_data_action.dart';
import 'package:domain_visualiser/enums/auth/auth_step_enum.dart';
import 'package:domain_visualiser/extensions/redux/store_extensions.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/services/auth_service.dart';
import 'package:redux/redux.dart';

class SignInWithAppleMiddleware
    extends TypedMiddleware<AppState, SignInWithAppleAction> {
  SignInWithAppleMiddleware(AuthService authService)
      : super((store, action, next) async {
          next(action);

          try {
            store.dispatch(
                StoreAuthStepAction(step: AuthStepEnum.contactingApple));

            final appleIdCredential = await authService.getAppleCredential();

            store.dispatch(
                StoreAuthStepAction(step: AuthStepEnum.signingInWithFirebase));

            // We don't do anyting with the UserData object here as the
            // authStateChanges stream will emit the same object and the state is
            // changed there.
            final authUserData = await authService.signInWithApple(
                credential: appleIdCredential);

            store.dispatch(StoreAuthUserDataAction(authUserData: authUserData));
            store.dispatch(
                StoreAuthStepAction(step: AuthStepEnum.waitingForInput));
          } catch (error, trace) {
            store.dispatchProblem(error, trace);
          }
        });
}
