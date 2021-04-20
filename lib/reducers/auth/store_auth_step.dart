import 'package:domain_visualiser/actions/auth/store_auth_step_action.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:redux/redux.dart';

class StoreAuthStepReducer extends TypedReducer<AppState, StoreAuthStepAction> {
  StoreAuthStepReducer()
      : super((state, action) => state.copyWith(authStep: action.step));
}
