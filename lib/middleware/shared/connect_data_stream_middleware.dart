import 'package:codraw/actions/shared/connect_data_stream_action.dart';
import 'package:codraw/extensions/redux/store_extensions.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:codraw/sync/graph_sync_backend.dart';
import 'package:redux/redux.dart';

class ConnectDataStreamMiddleware
    extends TypedMiddleware<AppState, ConnectDataStreamAction> {
  ConnectDataStreamMiddleware(GraphSyncBackend backend)
      : super((store, action, next) async {
          next(action);

          try {
            backend.connect(action.section);
            // switch (action.section) {
            //   case SyncSection.profileData:
            //     // databaseService.connectProfileData(uid: store.state.authUserData?.uid ?? '-');
            //     break;
            //   case SyncSection.classBoxes:
            //     break;
            // }
          } catch (error, trace) {
            store.dispatchProblem(error, trace);
          }
        });
}
