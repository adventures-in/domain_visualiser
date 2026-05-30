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
          // Read previous state BEFORE the reducer applies the update — the
          // only place we can diff against the on-store version.
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
