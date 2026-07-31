import 'package:codraw/actions/redux_action.dart';
import 'package:codraw/sync/sync_section.dart';
import 'package:codraw/graph/graph_envelope.dart';

/// A backend that persists graph nodes and streams remote changes back into
/// the Redux store.
///
/// Today the only implementation is [FirestoreBackend]. The seam exists so the
/// concrete transport can change (Firestore now; an Aiko/MQTT or CRDT peer
/// transport later) without touching middleware — only `ReduxBundle` names the
/// concrete backend.
///
/// **Scope (task #10, 2026-05-31; cage-match fixes 2026-05-31):** the contract
/// carries the generic [GraphNode] envelope. The earlier draft kept legacy
/// envelope-less `addNode`/`updateNode` entry points "for unported callers";
/// nothing actually called them and they offered a way to ship writes without
/// CRDT metadata, so they've been removed. Every persistence path must go
/// through [addGraphNode]/[updateGraphNode] and arrive with stamps.
abstract interface class GraphSyncBackend {
  /// Actions produced by remote changes, to be dispatched into the store.
  ///
  /// Connected to the store once on app load and kept open for the app's life.
  Stream<ReduxAction> get actionStream;

  /// Begin observing [section]; changes are emitted on [actionStream].
  void connect(SyncSection section);

  /// Stop observing [section].
  void disconnect(SyncSection section);

  /// Persist a stamped envelope for a newly-created node. Implementations must
  /// merge with any pre-existing on-wire copy (two replicas can race a create
  /// for the same id) so the surviving doc reflects both stamps.
  Future<void> addGraphNode(GraphNode node);

  /// Persist a partial-update envelope; only the units present in
  /// [GraphNode.stamps] are considered authored by this write. Implementations
  /// must merge with the on-wire copy so absent units retain their existing
  /// stamps.
  Future<void> updateGraphNode(GraphNode node);
}
