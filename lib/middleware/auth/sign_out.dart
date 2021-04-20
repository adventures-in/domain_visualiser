import 'package:domain_visualiser/actions/auth/sign_out_action.dart';
import 'package:domain_visualiser/actions/auth/store_auth_step_action.dart';
import 'package:domain_visualiser/enums/auth/auth_step_enum.dart';
import 'package:domain_visualiser/extensions/redux/store_extensions.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/services/auth_service.dart';
import 'package:redux/redux.dart';

class SignOutMiddleware extends TypedMiddleware<AppState, SignOutAction> {
  SignOutMiddleware(AuthService authService)
      : super((store, action, next) async {
          next(action);

          try {
            // set the auth step and use the service to sign out
            store.dispatch(StoreAuthStepAction(step: AuthStepEnum.signingOut));
            await authService.signOut();
          } catch (error, trace) {
            store.dispatchProblem(error, trace);
          }
        });
}
