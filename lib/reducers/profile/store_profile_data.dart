import 'package:domain_visualiser/actions/profile/store_profile_action.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:redux/redux.dart';

class StoreProfileDataReducer
    extends TypedReducer<AppState, StoreProfileAction> {
  StoreProfileDataReducer()
      : super((state, action) => state.copyWith(profileData: action.data));
}
