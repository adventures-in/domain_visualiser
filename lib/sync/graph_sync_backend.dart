import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/enums/database/database_section_enum.dart';
import 'package:domain_visualiser/graph/graph_envelope.dart';
import 'package:domain_visualiser/models/domain-objects/domain_object.dart';

/// A backend that persists graph nodes and streams remote changes back into
/// the Redux store.
///
/// Today the only implementation is [FirestoreBackend]. The seam exists so the
/// concrete transport can change (Firestore now; an Aiko/MQTT or CRDT peer
/// transport later) without touching middleware — only `ReduxBundle` names the
/// concrete backend.
///
/// **Scope (task #10, 2026-05-31):** the contract now carries the generic
/// [GraphNode] envelope alongside the legacy [DomainObject] entry points. The
/// envelope methods ([addGraphNode] / [updateGraphNode]) are what new
/// middleware uses; the old `addNode` / `updateNode` remain so any caller that
/// hasn't been ported yet still works (envelope-less writes degrade to LWW at
/// row grain, matching pre-task-#10 behaviour).
abstract interface class GraphSyncBackend {
  /// Actions produced by remote changes, to be dispatched into the store.
  ///
  /// Connected to the store once on app load and kept open for the app's life.
  Stream<ReduxAction> get actionStream;

  /// Begin observing [section]; changes are emitted on [actionStream].
  void connect(DatabaseSectionEnum section);

  /// Stop observing [section].
  void disconnect(DatabaseSectionEnum section);

  /// Persist a newly-created node (legacy / envelope-less path).
  Future<void> addNode(DomainObject node);

  /// Persist an update to an existing node (legacy / envelope-less path).
  Future<void> updateNode(DomainObject node);

  /// Persist a stamped envelope — the CRDT-aware path used by all new
  /// middleware. The transport must write the envelope alongside (or wrapping)
  /// the payload so a remote replica can recover stamps on read and merge
  /// concurrent edits via `mergeNodes`.
  Future<void> addGraphNode(GraphNode node);

  /// Persist a partial-update envelope; only the units present in
  /// [GraphNode.stamps] are considered authored by this write. Implementations
  /// must merge with the on-wire copy so absent units retain their existing
  /// stamps.
  Future<void> updateGraphNode(GraphNode node);
}
