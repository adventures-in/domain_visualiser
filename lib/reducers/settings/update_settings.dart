import 'package:codraw/actions/settings/update_settings_action.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:redux/redux.dart';

class UpdateSettingsReducer
    extends TypedReducer<AppState, UpdateSettingsAction> {
  UpdateSettingsReducer()
      : super((state, action) =>
            state.copyWith.settings(platform: action.platform));
}
