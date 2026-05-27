import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/enums/database/database_section_enum.dart';
import 'package:domain_visualiser/models/domain-objects/domain_object.dart';

/// A backend that persists graph nodes and streams remote changes back into
/// the Redux store.
///
/// Today the only implementation is [FirestoreBackend]. The seam exists so the
/// concrete transport can change (Firestore now; an Aiko/MQTT or CRDT peer
/// transport later) without touching middleware — only `ReduxBundle` names the
/// concrete backend.
///
/// Scope (honest, per cage-match #4): this contract is still **Redux-coupled**
/// ([actionStream] is a `Stream<ReduxAction>`) and carries domvis's own
/// [DomainObject], not the generic stamped `GraphNode`. Widening it to the
/// `GraphNode` envelope + CRDT changesets — the step that actually lets an
/// agent-peer or MQTT transport publish through this seam — is the next
/// increment. See `docs/adr/0001-graph-envelope.md`.
abstract interface class GraphSyncBackend {
  /// Actions produced by remote changes, to be dispatched into the store.
  ///
  /// Connected to the store once on app load and kept open for the app's life.
  Stream<ReduxAction> get actionStream;

  /// Begin observing [section]; changes are emitted on [actionStream].
  void connect(DatabaseSectionEnum section);

  /// Stop observing [section].
  void disconnect(DatabaseSectionEnum section);

  /// Persist a newly-created node. Takes [DomainObject] (not a concrete union
  /// case) so creation and update share one symmetric contract.
  Future<void> addNode(DomainObject node);

  /// Persist an update to an existing node.
  Future<void> updateNode(DomainObject node);
}
