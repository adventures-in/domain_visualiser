import 'package:codraw/actions/domain-objects/clear_class_boxes_action.dart';
import 'package:codraw/graph/class_box_schema.dart';
import 'package:codraw/graph/hlc_manager.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:codraw/sync/graph_sync_backend.dart';
import 'package:redux/redux.dart';

/// Tombstones every currently-visible [ClassBox] in response to a
/// [ClearClassBoxesAction].
///
/// Each box is deleted through a partial tombstone envelope ([classBoxTombstone])
/// persisted via [GraphSyncBackend.updateGraphNode] — the same read-merge-write
/// path as any edit — so Clear converges with concurrent peer writes instead of
/// clobbering them, and a peer that re-adds a box after our tombstone (higher
/// HLC) wins. We tombstone only the *visible* set (`state.classBoxes` is already
/// the non-deleted projection), so re-issuing Clear on an empty canvas is a
/// no-op rather than re-stamping dead nodes.
class ClearClassBoxesMiddleware
    extends TypedMiddleware<AppState, ClearClassBoxesAction> {
  ClearClassBoxesMiddleware(
    GraphSyncBackend backend,
    HlcManager hlc,
    String origin,
  ) : super((store, action, next) async {
          next(action);

          for (final box in store.state.classBoxes) {
            await backend.updateGraphNode(
              classBoxTombstone(box.id, hlc: hlc, origin: origin),
            );
          }
        });
}
