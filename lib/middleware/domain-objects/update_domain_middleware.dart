import 'package:domain_visualiser/actions/domain-objects/update_domain_action.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/sync/graph_sync_backend.dart';
import 'package:redux/redux.dart';

class UpdateDomainMiddleware
    extends TypedMiddleware<AppState, UpdateDomainAction> {
  UpdateDomainMiddleware(GraphSyncBackend backend)
      : super((store, action, next) async {
          next(action);

          await backend.updateNode(action.object);
        });
}
