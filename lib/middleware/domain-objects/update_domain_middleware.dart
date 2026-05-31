import 'package:domain_visualiser/actions/domain-objects/update_domain_action.dart';
import 'package:domain_visualiser/graph/class_box_schema.dart';
import 'package:domain_visualiser/graph/hlc_manager.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/models/domain-objects/domain_object.dart';
import 'package:domain_visualiser/sync/graph_sync_backend.dart';
import 'package:redux/redux.dart';

/// Persists an update to an existing ClassBox **as a partial stamped envelope**
/// — only the merge units whose payload actually changed are restamped, so a
/// concurrent peer renaming the same box wins on its own unit while we win on
/// ours.
class UpdateDomainMiddleware
    extends TypedMiddleware<AppState, UpdateDomainAction> {
  UpdateDomainMiddleware(
    GraphSyncBackend backend,
    HlcManager hlc,
    String origin,
  ) : super((store, action, next) async {
          // Type guard — `UpdateDomainAction.object` is the abstract
          // [DomainObject], and a future variant (Edge, GroupBox, …) routing
          // through here without its own middleware would crash on the cast
          // below. Pass through to the reducer and exit; do not silently
          // swallow, but also do not throw before the reducer runs.
          if (action.object is! ClassBox) {
            next(action);
            return;
          }

          // ORDERING NOTE: we read store.state.classBoxes BEFORE calling
          // next(action). That requires this middleware run synchronously
          // ahead of any other middleware that might mutate the store state
          // for the same id (none exist today). If a future middleware in the
          // chain DOES dispatch a state-changing side effect on
          // UpdateDomainAction, register it AFTER UpdateDomainMiddleware in
          // createAppMiddleware so the "previous" read here is still pre-edit.
          final previous = _findClassBox(store.state, action.object.id);
          next(action);

          final node = classBoxToGraphNodePartial(
            updated: action.object as ClassBox,
            previous: previous,
            hlc: hlc,
            origin: origin,
          );
          // Nothing changed → skip the write to avoid generating an empty echo.
          if (node.stamps.isEmpty) return;
          await backend.updateGraphNode(node);
        });

  static ClassBox? _findClassBox(AppState state, String id) {
    for (final box in state.classBoxes) {
      if (box.id == id) return box;
    }
    return null;
  }
}
