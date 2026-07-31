import 'package:codraw/actions/auth/sign_out_action.dart';
import 'package:codraw/actions/auth/store_auth_step_action.dart';
import 'package:codraw/enums/auth/auth_step_enum.dart';
import 'package:codraw/extensions/redux/store_extensions.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:codraw/services/auth_service.dart';
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
