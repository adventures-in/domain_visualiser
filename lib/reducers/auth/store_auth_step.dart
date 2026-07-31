import 'package:codraw/actions/auth/store_auth_step_action.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:redux/redux.dart';

class StoreAuthStepReducer extends TypedReducer<AppState, StoreAuthStepAction> {
  StoreAuthStepReducer()
      : super((state, action) => state.copyWith(authStep: action.step));
}
