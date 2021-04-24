import 'package:domain_visualiser/actions/domain-objects/update_domain_action.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/services/database_service.dart';
import 'package:redux/redux.dart';

class UpdateDomainMiddleware
    extends TypedMiddleware<AppState, UpdateDomainAction> {
  UpdateDomainMiddleware(DatabaseService databaseService)
      : super((store, action, next) async {
          next(action);

          await databaseService.updateDomain(action.object);
        });
}
