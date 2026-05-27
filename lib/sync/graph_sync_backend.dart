import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/enums/database/database_section_enum.dart';
import 'package:domain_visualiser/models/domain-objects/domain_object.dart';

/// A backend that syncs graph nodes between the Redux store and some transport.
///
/// Today the only implementation is Firestore (`FirestoreBackend`); the point
/// of the seam is that the canvas can swap transports — Aiko/MQTT, a CRDT peer
/// mesh — without any middleware change. The store observes [actionStream]
/// (remote changes arrive as [ReduxAction]s to dispatch); local changes are
/// pushed via [addNode] / [updateNode].
///
/// This is also the seam an AI agent-peer writes through: an agent is just
/// another origin emitting node changesets over a backend, no human-specific
/// path required. See `docs/adr/0001-graph-envelope.md` and
/// `docs/adr/0002-agent-as-peer.md`.
abstract interface class GraphSyncBackend {
  /// Actions produced by remote changes, to be dispatched into the store.
  ///
  /// Connected to the store once on app load and kept open for the app's life.
  Stream<ReduxAction> get actionStream;

  /// Begin observing [section]; changes are emitted on [actionStream].
  void connect(DatabaseSectionEnum section);

  /// Stop observing [section].
  void disconnect(DatabaseSectionEnum section);

  /// Persist a newly-created node.
  Future<void> addNode(ClassBox node);

  /// Persist an update to an existing node.
  Future<void> updateNode(DomainObject node);
}
