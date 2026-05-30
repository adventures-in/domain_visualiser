import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:domain_visualiser/actions/domain-objects/store_class_boxes_action.dart';
import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/enums/database/database_section_enum.dart';
import 'package:domain_visualiser/extensions/redux/actions_stream_controller_extensions.dart';
import 'package:domain_visualiser/graph/class_box_schema.dart';
import 'package:domain_visualiser/graph/graph_envelope.dart';
import 'package:domain_visualiser/graph/hlc_manager.dart';
import 'package:domain_visualiser/models/domain-objects/domain_object.dart';
import 'package:domain_visualiser/sync/graph_sync_backend.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

/// A [GraphSyncBackend] backed by Cloud Firestore.
///
/// Observes collections, converts each document into a stamped [GraphNode],
/// merges it against the in-memory replica, and emits [ReduxAction]s carrying
/// the convergent [ClassBox] projection.
///
/// CRDT state lives here (rather than in the reducer) because the snapshot
/// listener is the only place that sees both the on-wire envelope and the
/// local-cache one. Middleware uses [addGraphNode]/[updateGraphNode] to inform
/// the backend of local writes so the cache stays authoritative for both
/// origins.
class FirestoreBackend implements GraphSyncBackend {
  /// A map of DatabaseSectionEnum to database location
  static const locationOf = <DatabaseSectionEnum, String>{
    DatabaseSectionEnum.classBoxes: 'domain-objects',
    DatabaseSectionEnum.profile: 'profile'
  };

  final FirebaseFirestore _firestore;

  /// Keep track of the subscriptions so we can cancel them later.
  final Map<DatabaseSectionEnum, StreamSubscription> _subscriptions = {};

  /// The [_eventsController] is connected to the redux [Store] via
  /// [actionStream] and is used to add actions to the stream where they will
  /// be dispatched.
  final StreamController<ReduxAction> _eventsController;

  /// HLC source used to stamp any envelope-less write coming through the
  /// legacy path so it still participates in the merge.
  final HlcManager _hlc;

  /// This client's origin id (used for echo-suppression).
  final String _origin;

  /// In-memory replica of every observed/written [GraphNode], keyed by id.
  /// Always reflects the **merged** view (local writes + remote echoes).
  final Map<String, GraphNode> _replica = {};

  FirestoreBackend({
    FirebaseFirestore? database,
    StreamController<ReduxAction>? eventsController,
    required HlcManager hlc,
    required String origin,
  })  : _firestore = database ?? FirebaseFirestore.instance,
        _eventsController = eventsController ?? StreamController<ReduxAction>(),
        _hlc = hlc,
        _origin = origin;

  @override
  void connect(DatabaseSectionEnum section) {
    try {
      _subscriptions[section] = _firestore
          .collection(locationOf[section]!)
          .snapshots()
          .listen((QuerySnapshot snapshot) {
        try {
          _absorbRemoteSnapshot(snapshot, section);
        } catch (error, trace) {
          _eventsController.addProblem(error, trace);
        }
      }, onError: _eventsController.addProblem);
    } catch (error, trace) {
      _eventsController.addProblem(error, trace);
    }
  }

  /// Merges every doc in [snapshot] into [_replica] and emits a
  /// [StoreClassBoxesAction] projecting the converged view.
  ///
  /// Echo-suppression: a doc whose envelope stamps are ALL from this origin
  /// and are byte-equal to what we already hold is skipped. A non-byte-equal
  /// echo (e.g. another tab issued a later HLC under a different origin id —
  /// by design two devices have distinct origins) is merged normally.
  void _absorbRemoteSnapshot(
      QuerySnapshot snapshot, DatabaseSectionEnum section) {
    if (section != DatabaseSectionEnum.classBoxes) return;
    var anyChange = false;
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final incoming = _readGraphNodeFromDoc(doc.id, data);
      // Advance HLC past every observed stamp so future local issues sort
      // strictly after every remote we've heard from.
      for (final s in incoming.stamps.values) {
        _hlc.observe(s.hlc);
      }
      final existing = _replica[incoming.id];
      if (existing == null) {
        _replica[incoming.id] = incoming;
        anyChange = true;
        continue;
      }
      if (_isPureLocalEcho(incoming, existing)) continue;
      final merged = mergeNodes(existing, incoming, classBoxSchema);
      if (!_stampsEqual(merged.stamps, existing.stamps)) {
        _replica[incoming.id] = merged;
        anyChange = true;
      }
    }
    if (!anyChange) return;
    _emitProjection();
  }

  /// Reads a [GraphNode] from a Firestore doc.
  ///
  /// If the doc carries an [envelopeKey] block, deserialize it. Otherwise
  /// (legacy row / envelope-less producer) fabricate a single row-grain stamp
  /// at the current HLC and our origin under a reserved unit name. The doc
  /// still participates in the merge — it just LWWs at row grain, matching
  /// pre-task-#10 behaviour.
  GraphNode _readGraphNodeFromDoc(String id, Map<String, dynamic> data) {
    final envelope = data[envelopeKey];
    if (envelope is Map) {
      final stampsRaw = (envelope['stamps'] as Map?) ?? const {};
      final stamps = <String, FieldStamp>{};
      stampsRaw.forEach((k, v) {
        stamps[k as String] =
            FieldStamp.fromJson(Map<String, dynamic>.from(v as Map));
      });
      final payload = Map<String, Object?>.from(data)..remove(envelopeKey);
      return GraphNode(
        id: id,
        type: 'ClassBox',
        payload: payload,
        stamps: stamps,
      );
    }
    final stamp = FieldStamp(hlc: _hlc.issue(), origin: _origin);
    final payload = Map<String, Object?>.from(data);
    return GraphNode(
      id: id,
      type: 'ClassBox',
      payload: payload,
      stamps: {'__legacy_row__': stamp},
    );
  }

  bool _isPureLocalEcho(GraphNode incoming, GraphNode existing) {
    if (incoming.stamps.length != existing.stamps.length) return false;
    for (final entry in incoming.stamps.entries) {
      if (entry.value.origin != _origin) return false;
      final ours = existing.stamps[entry.key];
      if (ours == null || ours.hlc != entry.value.hlc) return false;
    }
    return true;
  }

  bool _stampsEqual(Map<String, FieldStamp> a, Map<String, FieldStamp> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null) return false;
      if (other.hlc != entry.value.hlc) return false;
      if (other.origin != entry.value.origin) return false;
    }
    return true;
  }

  void _emitProjection() {
    final boxes = _replica.values
        .where((n) => !n.isDeleted)
        .map((n) => graphNodeToClassBox(n))
        .toIList();
    _eventsController.add(StoreClassBoxesAction(boxes));
  }

  @override
  void disconnect(DatabaseSectionEnum section) =>
      _subscriptions[section]?.cancel();

  @override
  Future<void> addNode(DomainObject node) async {
    try {
      await _firestore
          .doc('${_getPath(node)}/${node.id}')
          .set(node.toJson());
    } catch (error, trace) {
      _eventsController.addProblem(error, trace);
    }
  }

  @override
  Future<void> updateNode(DomainObject node) async {
    try {
      await _firestore
          .doc('${_getPath(node)}/${node.id}')
          .update(node.toJson());
    } catch (error, trace) {
      _eventsController.addProblem(error, trace);
    }
  }

  @override
  Future<void> addGraphNode(GraphNode node) async {
    _replica[node.id] = node;
    try {
      final doc = _toFirestoreDoc(node);
      await _firestore
          .doc('${locationOf[DatabaseSectionEnum.classBoxes]}/${node.id}')
          .set(doc);
    } catch (error, trace) {
      _eventsController.addProblem(error, trace);
    }
  }

  @override
  Future<void> updateGraphNode(GraphNode node) async {
    // Merge into local replica first so the in-memory view reflects the write
    // immediately (and the upcoming Firestore echo will be a pure-echo skip).
    final existing = _replica[node.id];
    final merged =
        existing == null ? node : mergeNodes(existing, node, classBoxSchema);
    _replica[node.id] = merged;
    try {
      // Write the merged envelope (not just the partial) so a fresh reader
      // gets the complete stamp set on first read. We lean on Firestore's
      // last-write-wins at doc level + per-unit merge at read time to keep
      // concurrent writers convergent.
      final doc = _toFirestoreDoc(merged);
      await _firestore
          .doc('${locationOf[DatabaseSectionEnum.classBoxes]}/${node.id}')
          .set(doc);
    } catch (error, trace) {
      _eventsController.addProblem(error, trace);
    }
  }

  Map<String, dynamic> _toFirestoreDoc(GraphNode node) {
    return <String, dynamic>{
      ...node.payload,
      envelopeKey: {
        'stamps': node.stamps.map((k, v) => MapEntry(k, v.toJson())),
      },
    };
  }

  @override
  Stream<ReduxAction> get actionStream => _eventsController.stream;

  String _getPath(DomainObject object) {
    return object.when<String>(
        classBox: (String? type,
                String id,
                int? flightTime,
                String? userId,
                double left,
                double top,
                double right,
                double bottom,
                String? name,
                IList<String>? staticMethods,
                IList<String>? instanceMethods,
                IList<String>? staticVariables,
                IList<String>? instanceVariables) =>
            'domain-objects');
  }
}
