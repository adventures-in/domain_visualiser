import 'package:domain_visualiser/actions/app-init/plumb_streams_action.dart';
import 'package:domain_visualiser/extensions/redux/store_extensions.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/services/auth_service.dart';
import 'package:domain_visualiser/services/database_service.dart';
import 'package:redux/redux.dart';

class PlumbStreamsMiddleware
    extends TypedMiddleware<AppState, PlumbStreamsAction> {
  PlumbStreamsMiddleware(
      AuthService authService, DatabaseService databaseService)
      : super((store, action, next) async {
          next(action);

          /// We don't manage the subscription as the streams are expected
          /// to stay open for the whole lifetime of the app
          try {
            // databaseService.storeStream
            //     .listen(store.dispatch, onError: store.dispatchProblem);
            authService.storeStream
                .listen(store.dispatch, onError: store.dispatchProblem);
          } catch (error, trace) {
            store.dispatchProblem(error, trace);
          }
        });
}
