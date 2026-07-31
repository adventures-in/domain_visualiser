import 'package:codraw/actions/domain-objects/add_class_box_action.dart';
import 'package:codraw/graph/class_box_schema.dart';
import 'package:codraw/graph/hlc_manager.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:codraw/services/auth_service.dart';
import 'package:codraw/sync/graph_sync_backend.dart';
import 'package:redux/redux.dart';

/// Persists a newly-created ClassBox **as a stamped envelope** so concurrent
/// writers on other replicas converge under per-merge-unit LWW.
///
/// On create every unit is stamped fresh — the box has no prior state for any
/// peer to disagree with.
class AddClassBoxMiddleware
    extends TypedMiddleware<AppState, AddClassBoxAction> {
  AddClassBoxMiddleware(
    GraphSyncBackend backend,
    AuthService authService,
    HlcManager hlc,
    String origin,
  ) : super((store, action, next) async {
          next(action);

          final userId = await authService.getCurrentUserId();
          final classBox = action.classBox.copyWith(userId: userId);
          final node = classBoxToGraphNode(classBox, hlc: hlc, origin: origin);
          await backend.addGraphNode(node);
        });
}
