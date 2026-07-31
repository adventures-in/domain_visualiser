import 'package:codraw/actions/auth/sign_out_action.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:redux/redux.dart';

class SignOutReducer extends TypedReducer<AppState, SignOutAction> {
  SignOutReducer()
      : super((state, action) => state.copyWith(profileData: null));
}
