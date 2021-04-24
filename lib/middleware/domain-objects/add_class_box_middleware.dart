import 'package:domain_visualiser/actions/domain-objects/add_class_box_action.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/services/auth_service.dart';
import 'package:domain_visualiser/services/database_service.dart';
import 'package:redux/redux.dart';

class AddClassBoxMiddleware
    extends TypedMiddleware<AppState, AddClassBoxAction> {
  AddClassBoxMiddleware(
      DatabaseService databaseService, AuthService authService)
      : super((store, action, next) async {
          next(action);

          final userId = await authService.getCurrentUserId();

          await databaseService
              .addClassBox(action.classBox.copyWith(userId: userId));
        });
}
