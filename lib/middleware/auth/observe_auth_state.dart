import 'package:domain_visualiser/actions/auth/observe_auth_state_action.dart';
import 'package:domain_visualiser/extensions/redux/store_extensions.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/services/auth_service.dart';
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
