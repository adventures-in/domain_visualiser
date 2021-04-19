import 'package:domain_visualiser/actions/shared/connect_database_action.dart';
import 'package:domain_visualiser/enums/database/database_section_enum.dart';
import 'package:domain_visualiser/extensions/store_extensions.dart';
import 'package:domain_visualiser/models/app_state/app_state.dart';
import 'package:domain_visualiser/services/database_service.dart';
import 'package:redux/redux.dart';

class OpenDatabaseSinkMiddleware
    extends TypedMiddleware<AppState, ConnectDatabaseAction> {
  OpenDatabaseSinkMiddleware(DatabaseService databaseService)
      : super((store, action, next) async {
          next(action);

          try {
            switch (action.section) {
              case DatabaseSectionEnum.profileData:
                // databaseService.connectProfileData(uid: store.state.authUserData?.uid ?? '-');
                break;
              case DatabaseSectionEnum.classBoxes:
                // databaseService.connectClassBoxesCollection();
                break;
            }
          } catch (error, trace) {
            store.dispatchProblem(error, trace);
          }
        });
}
