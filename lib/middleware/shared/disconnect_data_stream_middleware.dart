import 'package:codraw/actions/shared/connect_data_stream_action.dart';
import 'package:codraw/extensions/redux/store_extensions.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:codraw/sync/graph_sync_backend.dart';
import 'package:redux/redux.dart';

class DisconnectDataStreamMiddleware
    extends TypedMiddleware<AppState, ConnectDataStreamAction> {
  DisconnectDataStreamMiddleware(GraphSyncBackend backend)
      : super((store, action, next) async {
          next(action);

          try {
            backend.disconnect(action.section);
          } catch (error, trace) {
            store.dispatchProblem(error, trace);
          }
        });
}
