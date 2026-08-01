import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:codraw/actions/domain-objects/store_class_boxes_action.dart';
import 'package:codraw/actions/redux_action.dart';
import 'package:codraw/sync/sync_section.dart';
import 'package:codraw/extensions/redux/actions_stream_controller_extensions.dart';
import 'package:codraw/graph/class_box_schema.dart';
import 'package:codraw/graph/schema_registry.dart';
import 'package:codraw/models/domain-objects/domain_object.dart'
    show ClassBox;
import 'package:codraw/graph/graph_envelope.dart';
import 'package:codraw/graph/hlc_manager.dart';
import 'package:codraw/sync/graph_sync_backend.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart' show debugPrint;

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
  /// A map of SyncSection to database location. The classBoxes collection name
  /// is the shared `classBoxesCollection` constant so the headless agent writer
  /// (tool/agent_draw.dart) can't drift onto a different collection.
  static const locationOf = <SyncSection, String>{
    SyncSection.classBoxes: classBoxesCollection,
    SyncSection.profile: 'profile'
  };

  final FirebaseFirestore _firestore;

  /// Keep track of the subscriptions so we can cancel them later.
  final Map<SyncSection, StreamSubscription> _subscriptions = {};

  /// The [_eventsController] is connected to the redux [Store] via
  /// [actionStream] and is used to add actions to the stream where they will
  /// be dispatched.
  final StreamController<ReduxAction> _eventsController;

  /// HLC source used to stamp any envelope-less write coming through the
  /// legacy path so it still participates in the merge.
  final HlcManager _hlc;

  /// This client's origin id (used for echo-suppression).
  final String _origin;

  /// Maps a doc's declared `type` to its merge schema. Slice 0 registers ClassBox
  /// alone, so behaviour is identical to the pre-registry hardwired `classBoxSchema`
  /// — the generalization is the point, not a behaviour change.
  final SchemaRegistry _registry;

  /// In-memory replica of every observed/written [GraphNode], keyed by id.
  /// Always reflects the **merged** view (local writes + remote echoes).
  final Map<String, GraphNode> _replica = {};

  FirestoreBackend({
    FirebaseFirestore? database,
    StreamController<ReduxAction>? eventsController,
    required HlcManager hlc,
    required String origin,
    SchemaRegistry? registry,
  })  : _firestore = database ?? FirebaseFirestore.instance,
        _eventsController = eventsController ?? StreamController<ReduxAction>(),
        _hlc = hlc,
        _origin = origin,
        _registry = registry ?? defaultRegistry;

  /// The [NodeSchema] for an ALREADY-ADMITTED node type, or fail closed.
  ///
  /// Every merge input is a node whose type the door already admitted (a
  /// door-validated remote doc, or a `_replica`/local node built as a registered
  /// type), so this always resolves in practice. The `??`-throw is the structural
  /// fail-closed backstop — NEVER a default: a null here means a type slipped past
  /// the door, which must quarantine per-doc, not silently merge under the wrong
  /// schema (the "guard the window" collapse the registry exists to remove).
  NodeSchema _schemaOrThrow(String type) =>
      _registry.nodeSchemaFor(type) ??
      (throw StateError('no schema for admitted node type "$type"'));

  @override
  void connect(SyncSection section) {
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

  /// Merges every change in [snapshot] into [_replica] and emits a
  /// [StoreClassBoxesAction] projecting the converged view.
  ///
  /// We iterate [QuerySnapshot.docChanges] rather than [QuerySnapshot.docs] so
  /// that [DocumentChangeType.removed] events strip the corresponding entry
  /// from [_replica] — otherwise a hard-deleted Firestore doc (out-of-band
  /// console delete, manual cleanup, anything that bypasses our tombstone
  /// path) would leave a zombie in the in-memory cache.
  ///
  /// Echo-suppression: a doc whose envelope stamps are ALL from this origin
  /// and are byte-equal to what we already hold is skipped. A non-byte-equal
  /// echo (e.g. another tab issued a later HLC under a different origin id —
  /// by design two devices have distinct origins) is merged normally.
  void _absorbRemoteSnapshot(
      QuerySnapshot snapshot, SyncSection section) {
    if (section != SyncSection.classBoxes) return;
    var anyChange = false;
    for (final change in snapshot.docChanges) {
      final doc = change.doc;
      if (change.type == DocumentChangeType.removed) {
        if (_replica.remove(doc.id) != null) anyChange = true;
        continue;
      }
      // Per-doc fail-closed backstop over the WHOLE change body. The door
      // (_tryReadValidNode) removes every KNOWN throw source, but the post-door
      // steps run here in the batch loop and can still throw on remote bytes —
      // e.g. mergeNodes fails closed (StateError) on equal stamps with a
      // divergent payload, a shape a foreign producer can craft. A throw here
      // would abort the snapshot mid-docChanges and route EVERY user to
      // ProblemPage. Wrapping the body makes absorb DoS-immunity STRUCTURAL (one
      // doc skipped, never the batch), matching _emitProjection's per-node guard,
      // rather than depending on the invariant that nothing after the door throws.
      try {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;
        // Single trust boundary for unvalidated remote input: quarantine a
        // malformed/hostile doc (skip + breadcrumb) rather than letting it throw
        // and drop EVERY user's canvas to ProblemPage. See _tryReadValidNode.
        final incoming = _tryReadValidNode(doc.id, data);
        // Quarantine policy on an EXISTING id (asymmetry vs `removed` above, which
        // strips the replica): a `modified` event that turns poison RETAINS the
        // last-known-good replica entry rather than dropping it. A corrupt/partial
        // overwrite is treated as availability-preserving noise, not a delete — we
        // keep showing the last good state instead of flickering the node out.
        // (A genuine removal still arrives as a `removed` change and does strip.)
        if (incoming == null) continue;
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
        final merged = mergeNodes(existing, incoming, _schemaOrThrow(existing.type));
        if (!_stampsEqual(merged.stamps, existing.stamps)) {
          _replica[incoming.id] = merged;
          anyChange = true;
        }
      } catch (error) {
        _quarantineRemoteDoc(doc.id, error);
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
    // The type discriminator: an explicit sibling `_type`, or ABSENT → 'ClassBox'.
    // No current writer emits `_type`, so every existing doc reads as a ClassBox —
    // this is the only behavioural change in Slice 0, and it is a no-op for today's
    // data. `_type` is identity, not payload, so it is stripped like `envelopeKey`.
    final type = (data[typeKey] as String?) ?? 'ClassBox';
    final envelope = data[envelopeKey];
    if (envelope is Map) {
      final stampsRaw = (envelope['stamps'] as Map?) ?? const {};
      final stamps = <String, FieldStamp>{};
      stampsRaw.forEach((k, v) {
        stamps[k as String] =
            FieldStamp.fromJson(Map<String, dynamic>.from(v as Map));
      });
      final payload = Map<String, Object?>.from(data)
        ..remove(envelopeKey)
        ..remove(typeKey);
      return GraphNode(
        id: id,
        type: type,
        payload: payload,
        stamps: stamps,
      );
    }
    final stamp = FieldStamp(hlc: _hlc.issue(), origin: _origin);
    final payload = Map<String, Object?>.from(data)..remove(typeKey);
    return GraphNode(
      id: id,
      type: type,
      payload: payload,
      stamps: {NodeSchema.legacyRowUnit: stamp},
    );
  }

  /// Reads and VALIDATES a remote doc into a node, or returns null to
  /// QUARANTINE it. This is the single trust boundary for unvalidated remote
  /// input — the whole point of agent-as-peer is accepting writes from
  /// producers we do not control (a foreign app, a partial write, a hand-edited
  /// console doc), so exactly one malformed doc must NOT be able to sink the
  /// batch or DoS every user's canvas. Every failure here is a per-doc skip +
  /// breadcrumb, never an [addProblem] (which routes the whole app to
  /// ProblemPage — the DoS this closes). This is the classBox absorb/merge path
  /// (`SyncSection.classBoxes` → `type: 'ClassBox'`); an edge sync path, when it
  /// exists, needs its own equivalent door.
  ///
  /// The door validates the PRECONDITIONS the post-door steps (`_hlc.observe`,
  /// [mergeNodes], [_emitProjection]) rely on but which run OUTSIDE this per-doc
  /// guard, where a throw would sink the whole batch to ProblemPage. It rejects:
  /// reserved field names; an unparseable envelope; a stamp that cannot order
  /// (empty origin/hlc, NO stamps, or a non-empty but UNPARSEABLE hlc —
  /// [HlcManager.observe] calls `Hlc.parse`); and a payload that cannot project
  /// (`Hlc.parse`-valid stamps still leave a wrong-typed geometry field that
  /// [graphNodeToClassBox] would throw on). This is not a proof that no post-door
  /// step can ever throw — [_emitProjection] additionally fails closed per-node
  /// as a structural backstop — but it removes every KNOWN throw source at the
  /// door, so one bad doc is skipped, never the batch.
  GraphNode? _tryReadValidNode(String id, Map<String, dynamic> data) {
    try {
      // face (d): a remote doc carrying a Firestore-reserved `__.*__` field name
      // would 400 on our next merge-write-back — reject it at the door rather
      // than absorb it and re-emit it through the merge fan-in.
      if (!_noReservedFieldNames(data)) {
        throw const FormatException('remote doc carries a reserved __.*__ field name');
      }
      final node = _readGraphNodeFromDoc(id, data);
      // The new degenerate state the type-aware read path introduces: a doc
      // declaring a type this client does not have a schema for. Quarantine it at
      // the door (skip+breadcrumb) — NEVER merge it under the wrong schema (silent
      // field loss) and never let it reach a merge site where _schemaOrThrow would
      // throw mid-batch. This is DoS-safe AND forward-compatible: an older client
      // skips a newer node kind gracefully. `type` ABSENT already resolved to the
      // registered 'ClassBox' in _readGraphNodeFromDoc, so only a PRESENT-but-
      // unregistered type reaches here.
      if (!_registry.hasNodeType(node.type)) {
        throw FormatException('unregistered node type "${node.type}"');
      }
      // A node with NO stamps can neither order (LWW) nor echo-suppress — that is
      // corruption, not a concurrent edit. (Enveloped docs can carry an empty
      // `stamps` map; legacy/envelope-less docs always fabricate one stamp.)
      if (node.stamps.isEmpty) {
        throw const FormatException('node has no stamps — cannot order or echo-suppress');
      }
      // A stamp with a blank origin or hlc can neither order (LWW) nor
      // echo-suppress correctly — that is corruption, not a concurrent edit.
      for (final entry in node.stamps.entries) {
        final s = entry.value;
        if (s.origin.isEmpty || s.hlc.isEmpty) {
          throw FormatException('stamp "${entry.key}" has empty origin/hlc');
        }
        // A non-empty but unparseable hlc passes the isEmpty check yet throws in
        // _hlc.observe (Hlc.parse) back in the absorb loop, outside this guard.
        // Dry-run the parse here so it is quarantined at the door instead.
        if (!HlcManager.isValidHlc(s.hlc)) {
          throw FormatException('stamp "${entry.key}" has an unparseable hlc "${s.hlc}"');
        }
      }
      // Projectability is part of the trust boundary. A stamp-valid doc whose
      // payload has a wrong-typed field (e.g. `left: "banana"`) parses and
      // validates above, but `graphNodeToClassBox`'s `as num?` casts would throw
      // in [_emitProjection] — outside this per-doc guard, DoSing the whole
      // canvas. Dry-run the projection so an unprojectable node is quarantined
      // at the door instead.
      graphNodeToClassBox(node);
      return node;
    } catch (error) {
      _quarantineRemoteDoc(id, error);
      return null;
    }
  }

  /// Breadcrumb for a quarantined node: visible for debugging but deliberately
  /// NOT surfaced as an app Problem (that would defeat the DoS protection this
  /// method exists to provide). Called from every fail-closed site — the absorb
  /// door/body, the write-path merge, and the projection backstop — so the
  /// message stays source-neutral (a projection-backstop throw may be a locally
  /// built node, not remote bytes).
  void _quarantineRemoteDoc(String id, Object error) {
    debugPrint('FirestoreBackend: quarantined node "$id": $error');
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
    // Per-node fail-closed: every node in _replica entered via _tryReadValidNode
    // (which dry-runs projection) or was built locally, so a projection throw
    // here should be unreachable. But this is a batch-wide fan-in — one throw
    // would sink the WHOLE canvas — so make DoS-immunity STRUCTURAL rather than
    // dependent on that invariant: a future replica-insertion path or a schema
    // cast that grows a new tooth skips the one bad node, never the batch.
    final boxes = _replica.values.where((n) => !n.isDeleted).expand((n) {
      try {
        return [graphNodeToClassBox(n)];
      } catch (error) {
        _quarantineRemoteDoc(n.id, error);
        return const <ClassBox>[];
      }
    }).toIList();
    _eventsController.add(StoreClassBoxesAction(boxes));
  }

  @override
  void disconnect(SyncSection section) =>
      _subscriptions[section]?.cancel();

  @override
  Future<void> addGraphNode(GraphNode node) async {
    // A create goes through the same read-merge-write transaction as an
    // update, so two replicas that both call addGraphNode on the same id
    // converge instead of clobbering. Atomic-doc semantics matter most for
    // updates, but applying them uniformly keeps the code (and reasoning)
    // honest.
    await _writeMerged(node);
  }

  @override
  Future<void> updateGraphNode(GraphNode node) async {
    await _writeMerged(node);
  }

  /// Atomically reads the on-wire doc, merges [incoming] against it under
  /// [classBoxSchema], and writes the merged envelope back inside a Firestore
  /// transaction.
  ///
  /// Why a transaction (rather than `.set()` after an in-memory merge):
  /// concurrent writers with the *same* local replica each call `.set()` with
  /// their own merged document, and whichever lands last in Firestore wins —
  /// silently overwriting the other's edits in the durable store. (Live
  /// listeners converge in memory; a fresh-joining client reads the stale
  /// doc.) A transaction reads the current Firestore state inside the same
  /// atomic write, so the merge happens against the actual on-wire base. The
  /// merge logic itself is unchanged — [mergeNodes] is commutative — so this
  /// closes the durability hole without altering convergence semantics.
  Future<void> _writeMerged(GraphNode incoming) async {
    // Reflect the write in the local replica immediately AND re-project so the
    // canvas updates optimistically — the Firestore echo of our own write is
    // suppressed (pure-local-echo / stamps-equal in _absorbRemoteSnapshot), so
    // without this emit a local add/update/tombstone would never reach the UI.
    // A later echo carrying a concurrent remote edit still reconciles the view.
    final localExisting = _replica[incoming.id];
    final localMerged = localExisting == null
        ? incoming
        : mergeNodes(localExisting, incoming, _schemaOrThrow(localExisting.type));
    _replica[incoming.id] = localMerged;
    _emitProjection();

    final ref = _firestore
        .doc('${locationOf[SyncSection.classBoxes]}/${incoming.id}');
    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final remoteData = snap.data();
        // A transaction read is ALSO unvalidated remote input — the SAME single
        // trust boundary as the absorb path. If a poison on-wire doc sits at this
        // id, a bare read would throw here → caught below → addProblem → whole-
        // canvas DoS on any local edit to that id (the exact class this closes).
        // Quarantine it and treat a quarantined base as "no remote base", so our
        // validated write wins and self-heals the poison doc on the way out.
        final remoteNode = (remoteData == null)
            ? null
            : _tryReadValidNode(incoming.id, remoteData);
        // No usable remote base — genuinely absent OR quarantined poison — so
        // write the LOCAL merge (localExisting ⊔ incoming), not `incoming` alone.
        // For a fresh create localMerged == incoming; for a self-heal over a
        // poison doc it preserves units that lived only in localExisting, which a
        // partial `incoming` would otherwise drop on the wire (availability +
        // integrity, not just availability).
        // Structural fail-closed on the MERGE too — the sibling site of the
        // absorb-loop wrap. A poison remote base can merge to a StateError
        // (equal stamp / divergent payload, craftable by a producer forging our
        // origin + replaying an hlc); that must quarantine + self-heal to our
        // local merge, NOT fall through to the outer catch's addProblem (which
        // would DoS the whole canvas on a local edit). Both merge sites are now
        // per-doc fail-closed.
        GraphNode mergedForWire;
        if (remoteNode == null) {
          mergedForWire = localMerged;
        } else {
          try {
            mergedForWire = mergeNodes(remoteNode, incoming, _schemaOrThrow(remoteNode.type));
          } catch (error) {
            _quarantineRemoteDoc(incoming.id, error);
            mergedForWire = localMerged;
          }
        }
        tx.set(ref, _toFirestoreDoc(mergedForWire));
      });
    } catch (error, trace) {
      _eventsController.addProblem(error, trace);
    }
  }

  Map<String, dynamic> _toFirestoreDoc(GraphNode node) {
    final doc = <String, dynamic>{
      ...node.payload,
      envelopeKey: {
        'stamps': node.stamps.map((k, v) => MapEntry(k, v.toJson())),
      },
    };
    // Enforce the reserved-field-name invariant at the single write door, so
    // ANY producer (a future app schema, a tool, a test) is caught here rather
    // than by a live 400 — the guard test only proves today's callers. `assert`
    // fires in dev/test/CI (where every producer runs) at zero release cost; a
    // reserved key can only be introduced by a code change, which those catch.
    assert(_noReservedFieldNames(doc),
        'a Firestore field name/key matches the reserved `__.*__` pattern and '
        'would be rejected with 400 — see reserved_field_names_test.dart');
    return doc;
  }

  static final RegExp _reservedFieldName = RegExp(r'^__.*__$');

  /// Recursively verifies no field name / nested map key in [value] matches
  /// Firestore's reserved `__.*__` pattern.
  static bool _noReservedFieldNames(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (_reservedFieldName.hasMatch(entry.key.toString())) return false;
        if (!_noReservedFieldNames(entry.value)) return false;
      }
    } else if (value is List) {
      for (final e in value) {
        if (!_noReservedFieldNames(e)) return false;
      }
    }
    return true;
  }

  @override
  Stream<ReduxAction> get actionStream => _eventsController.stream;
}
