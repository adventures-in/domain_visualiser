import 'package:domain_visualiser/actions/domain-objects/save_new_class_box_action.dart';
import 'package:domain_visualiser/models/app_state/app_state.dart';
import 'package:domain_visualiser/services/database_service.dart';
import 'package:redux/redux.dart';

class SaveNewClassBoxMiddleware
    extends TypedMiddleware<AppState, SaveNewClassBoxAction> {
  SaveNewClassBoxMiddleware(DatabaseService databaseService)
      : super((store, action, next) async {
          next(action);

          await databaseService.saveClassBox(action.classBox);
        });
}
