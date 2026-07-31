import 'package:codraw/actions/profile/store_profile_action.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:redux/redux.dart';

class StoreProfileDataReducer
    extends TypedReducer<AppState, StoreProfileAction> {
  StoreProfileDataReducer()
      : super((state, action) => state.copyWith(profileData: action.data));
}
