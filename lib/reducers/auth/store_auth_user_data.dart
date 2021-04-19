import 'package:domain_visualiser/actions/auth/store_auth_user_data_action.dart';
import 'package:domain_visualiser/enums/auth/auth_step_enum.dart';
import 'package:domain_visualiser/models/app_state/app_state.dart';
import 'package:redux/redux.dart';

class StoreAuthUserDataReducer
    extends TypedReducer<AppState, StoreAuthUserDataAction> {
  StoreAuthUserDataReducer()
      : super((state, action) {
          // guard statement to avoid further null checks
          if (action.authUserData == null) {
            return state.copyWith(
                authUserData: null, authStep: AuthStepEnum.waitingForInput);
          }

          return state.copyWith(
              authUserData: action.authUserData,
              authStep: AuthStepEnum.waitingForInput);
        });
}
