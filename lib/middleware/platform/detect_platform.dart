import 'package:domain_visualiser/actions/platform/detect_platform_action.dart';
import 'package:domain_visualiser/actions/settings/update_settings_action.dart';
import 'package:domain_visualiser/extensions/redux/store_extensions.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/services/platform_service.dart';
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
