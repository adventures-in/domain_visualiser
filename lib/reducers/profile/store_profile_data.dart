import 'package:domain_visualiser/actions/profile/store_profile_data_action.dart';
import 'package:domain_visualiser/models/app_state/app_state.dart';
import 'package:redux/redux.dart';

class StoreProfileDataReducer
    extends TypedReducer<AppState, StoreProfileDataAction> {
  StoreProfileDataReducer()
      : super((state, action) => state.copyWith(profileData: action.data));
}
