import 'package:codraw/actions/platform/detect_platform_action.dart';
import 'package:codraw/actions/settings/update_settings_action.dart';
import 'package:codraw/extensions/redux/store_extensions.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:codraw/services/platform_service.dart';
import 'package:redux/redux.dart';

class DetectPlatformMiddleware
    extends TypedMiddleware<AppState, DetectPlatformAction> {
  DetectPlatformMiddleware(PlatformService platformService)
      : super((store, action, next) async {
          next(action);

          try {
            final platform = platformService.detectPlatform();
            store.dispatch(UpdateSettingsAction(platform: platform));
          } catch (error, trace) {
            store.dispatchProblem(error, trace);
          }
        });
}
