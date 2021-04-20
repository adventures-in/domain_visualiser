import 'package:domain_visualiser/actions/settings/update_settings_action.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:redux/redux.dart';

class UpdateSettingsReducer
    extends TypedReducer<AppState, UpdateSettingsAction> {
  UpdateSettingsReducer()
      : super((state, action) =>
            state.copyWith.settings(platform: action.platform));
}
