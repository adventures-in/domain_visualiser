import 'package:domain_visualiser/actions/shared/connect_database_action.dart';
import 'package:domain_visualiser/extensions/store_extensions.dart';
import 'package:domain_visualiser/models/app_state/app_state.dart';
import 'package:domain_visualiser/services/database_service.dart';
import 'package:redux/redux.dart';

class CloseDatabaseSinkMiddleware
    extends TypedMiddleware<AppState, ConnectDatabaseAction> {
  CloseDatabaseSinkMiddleware(DatabaseService databaseService)
      : super((store, action, next) async {
          next(action);

          try {
            // databaseService.disconnect(action.section);
          } catch (error, trace) {
            store.dispatchProblem(error, trace);
          }
        });
}
