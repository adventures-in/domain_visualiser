import 'package:domain_visualiser/actions/shared/connect_data_stream_action.dart';
import 'package:domain_visualiser/extensions/redux/store_extensions.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/services/database_service.dart';
import 'package:redux/redux.dart';

class ConnectDataStreamMiddleware
    extends TypedMiddleware<AppState, ConnectDataStreamAction> {
  ConnectDataStreamMiddleware(DatabaseService databaseService)
      : super((store, action, next) async {
          next(action);

          try {
            databaseService.connect(action.section);
            // switch (action.section) {
            //   case DatabaseSectionEnum.profileData:
            //     // databaseService.connectProfileData(uid: store.state.authUserData?.uid ?? '-');
            //     break;
            //   case DatabaseSectionEnum.classBoxes:
            //     break;
            // }
          } catch (error, trace) {
            store.dispatchProblem(error, trace);
          }
        });
}
