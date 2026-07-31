import 'package:codraw/actions/auth/observe_auth_state_action.dart';
import 'package:codraw/extensions/redux/store_extensions.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:codraw/services/auth_service.dart';
import 'package:redux/redux.dart';

class ObserveAuthStateMiddleware
    extends TypedMiddleware<AppState, ObserveAuthStateAction> {
  ObserveAuthStateMiddleware(AuthService authService)
      : super((store, action, next) async {
          next(action);

          try {
            authService.connectAuthStateToStore();
          } catch (error, trace) {
            store.dispatchProblem(error, trace);
          }
        });
}
