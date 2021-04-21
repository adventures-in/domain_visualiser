import 'package:domain_visualiser/actions/shared/connect_data_stream_action.dart';
import 'package:domain_visualiser/extensions/redux/store_extensions.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/services/database_service.dart';
import 'package:redux/redux.dart';

class DisconnectDataStreamMiddleware
    extends TypedMiddleware<AppState, ConnectDataStreamAction> {
  DisconnectDataStreamMiddleware(DatabaseService databaseService)
      : super((store, action, next) async {
          next(action);

          try {
            databaseService.disconnect(action.section);
          } catch (error, trace) {
            store.dispatchProblem(error, trace);
          }
        });
}
