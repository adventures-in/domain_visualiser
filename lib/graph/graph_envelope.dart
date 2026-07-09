/// Generic, schema-agnostic envelope for a collaborative knowledge-graph node
/// or edge, plus the CRDT metadata needed to merge concurrent edits.
///
/// This is the *substrate type* that several apps in the Melbourne AI-builder
/// community are independently reinventing (domain_visualiser's canvas, Engram's
/// knowledge graph, Aiko's pipeline graphs). The design goal is that the same
/// bytes can cross the wire between any of them: **generic in transit, typed at
/// the app edge** (the "hybrid" pole — see docs/adr/0001-graph-envelope.md).
///
/// It is deliberately implemented *here, inside domain_visualiser* rather than
/// in a shared package. By the rule of three, this is the 2nd independent
/// instantiation of the CRDT pattern (Engram is the 1st); the shared engine is
/// extracted only when a 3rd consumer wants it. Copying the pattern now keeps
/// mature, shipping Engram untouched.
library;

/// A Hybrid Logical Clock timestamp in its canonical, lexicographically-
/// sortable string form (the encoding used by `package:crdt`).
///
/// Stored as a `String` rather than a `package:crdt` `Hlc` so the envelope type
/// stays dependency-free and trivially serializable — *clock generation*
/// (increment/merge) is the app layer's job, *ordering* is all the envelope
/// needs and string comparison gives it causal order for free.
typedef HlcString = String;

/// The CRDT stamp on a single **merge unit** (see [NodeSchema]).
///
/// Carries the [hlc] that orders concurrent writes (last-writer-wins by
/// lexicographic HLC comparison) and the [origin] that wrote it.
///
/// [origin] is *redundant* with the node id embedded inside a `package:crdt`
/// HLC — but it is stored explicitly so that (a) echo-suppression
/// (`stamp.origin == myClientId`) needs no HLC parser, and (b) a producer that
/// doesn't use `package:crdt`'s HLC encoding is still a valid participant. This
/// denormalization is the chosen trade — see ADR-0001, decision 1.
class FieldStamp {
  const FieldStamp({required this.hlc, required this.origin});

  factory FieldStamp.fromJson(Map<String, dynamic> json) => FieldStamp(
        hlc: json['hlc'] as HlcString,
        origin: json['origin'] as String,
      );

  /// Orders this write against concurrent writes to the same merge unit.
  final HlcString hlc;

  /// The client id that produced this write (used for echo-suppression).
  final String origin;

  Map<String, dynamic> toJson() => {'hlc': hlc, 'origin': origin};

  /// True if this stamp wins last-writer-wins against [other].
  ///
  /// Higher HLC wins; ties (same wall-time + counter across two origins) break
  /// deterministically by origin so every replica converges identically.
  bool wins(FieldStamp other) {
    final cmp = hlc.compareTo(other.hlc);
    if (cmp != 0) return cmp > 0;
    return origin.compareTo(other.origin) > 0;
  }
}

/// Declares how an app's payload fields group into **merge units** — the
/// atomic granularity at which last-writer-wins is applied.
///
/// This is the crux of the envelope. "Per-field LWW" is simultaneously too
/// coarse and too fine: domain_visualiser's `left/top/right/bottom` must move as
/// *one* unit or a concurrent drag+drag tears the box across replicas, while
/// `name` is its own independent unit so Alice can rename a box while Bob drags
/// it without either edit clobbering the other. The grain is an *app-level*
/// decision; the engine just honours the declaration.
///
/// Identity fields ([GraphNode.id], [GraphNode.type]) are immutable and never
/// belong to a merge unit. The reserved unit [tombstoneUnit] carries the
/// liveness flag so deletion LWWs against edits through the exact same path
/// (a late edit with a higher HLC resurrects; a late delete wins — uniformly).
class NodeSchema {
  const NodeSchema({required this.type, required this.mergeUnits});

  /// The discriminator that selects this schema (e.g. `'ClassBox'`).
  final String type;

  /// Merge-unit name → the payload field names that move together under it.
  final Map<String, List<String>> mergeUnits;

  /// Reserved merge unit holding the tombstone flag (payload key
  /// [tombstoneField], a `bool`). Present implicitly on every node.
  static const String tombstoneUnit = '__tomb__';

  /// Payload key under [tombstoneUnit]; `true` means deleted.
  static const String tombstoneField = '__deleted__';
}

/// A node in the collaborative graph.
///
/// [payload] holds the field *values* keyed by field name; [stamps] holds one
/// [FieldStamp] per merge unit declared by the node's [NodeSchema]. The two maps
/// are kept separate (rather than wrapping every value in a stamped cell) so the
/// payload serializes to exactly the shape an app already speaks — the CRDT
/// metadata rides alongside, not inside, the domain data.
class GraphNode {
  const GraphNode({
    required this.id,
    required this.type,
    required this.payload,
    required this.stamps,
  });

  factory GraphNode.fromJson(Map<String, dynamic> json) => GraphNode(
        id: json['id'] as String,
        type: json['type'] as String,
        payload: Map<String, Object?>.from(json['payload'] as Map),
        stamps: (json['stamps'] as Map).map(
          (k, v) => MapEntry(
            k as String,
            FieldStamp.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        ),
      );

  /// Stable identity; immutable, never stamped, never merged.
  final String id;

  /// Discriminator selecting the app deserializer / [NodeSchema]; immutable.
  final String type;

  /// Field name → value. Schema-agnostic: the engine never interprets these.
  final Map<String, Object?> payload;

  /// Merge-unit name → CRDT stamp.
  final Map<String, FieldStamp> stamps;

  /// True if a winning [NodeSchema.tombstoneUnit] stamp marks this deleted.
  bool get isDeleted => payload[NodeSchema.tombstoneField] == true;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'payload': payload,
        'stamps': stamps.map((k, v) => MapEntry(k, v.toJson())),
      };
}

/// The shared CRDT merge core, used by both [mergeNodes] and [mergeEdges].
///
/// For each merge unit present on either side, the higher-HLC stamp wins
/// ([FieldStamp.wins]); the winning side's payload fields for that unit are
/// taken. Because tombstones are just another unit, deletion/resurrection falls
/// out of the same loop. The operation is commutative, associative and
/// idempotent — re-applying any change converges to the same state, which is
/// what lets a dumb transport (Firestore, MQTT, …) deliver in any order.
///
/// [fieldsOf] maps each merge-unit name to the payload fields that move under
/// it (the schema's units plus the reserved tombstone unit). Living in exactly
/// one place means the LWW invariant has exactly one place to be got wrong.
(Map<String, Object?>, Map<String, FieldStamp>) _mergeUnits({
  required Map<String, Object?> localPayload,
  required Map<String, FieldStamp> localStamps,
  required Map<String, Object?> remotePayload,
  required Map<String, FieldStamp> remoteStamps,
  required Map<String, List<String>> fieldsOf,
}) {
  final units = {...localStamps.keys, ...remoteStamps.keys};
  final mergedPayload = <String, Object?>{...localPayload};
  final mergedStamps = <String, FieldStamp>{...localStamps};

  for (final unit in units) {
    final localStamp = localStamps[unit];
    final remoteStamp = remoteStamps[unit];

    // Remote wins this unit if local has no stamp, or remote's stamp beats it.
    final remoteWins =
        remoteStamp != null && (localStamp == null || remoteStamp.wins(localStamp));
    if (!remoteWins) continue;

    mergedStamps[unit] = remoteStamp;
    for (final field in fieldsOf[unit] ?? const <String>[]) {
      mergedPayload[field] = remotePayload[field];
    }
  }

  return (mergedPayload, mergedStamps);
}

/// Merges two replicas of the same node ([local].id == [remote].id) under
/// [schema], producing the convergent result. See [_mergeUnits] for the LWW
/// semantics; nodes contribute only their schema's units plus the tombstone.
GraphNode mergeNodes(GraphNode local, GraphNode remote, NodeSchema schema) {
  assert(local.id == remote.id, 'cannot merge distinct nodes');

  final (payload, stamps) = _mergeUnits(
    localPayload: local.payload,
    localStamps: local.stamps,
    remotePayload: remote.payload,
    remoteStamps: remote.stamps,
    fieldsOf: {
      ...schema.mergeUnits,
      NodeSchema.tombstoneUnit: const [NodeSchema.tombstoneField],
    },
  );

  return GraphNode(
    id: local.id,
    type: local.type,
    payload: payload,
    stamps: stamps,
  );
}

/// Declares the merge-unit grain for a [GraphEdge], exactly as [NodeSchema]
/// does for a node.
///
/// Endpoints ([GraphEdge.fromId], [GraphEdge.toId]) are *identity* — like
/// [GraphEdge.id]/[GraphEdge.type] they are immutable and never belong to a
/// merge unit, so they are deliberately NOT declared here. Only the mutable,
/// concurrently-editable payload has a grain.
class EdgeSchema {
  const EdgeSchema({required this.type, required this.mergeUnits});

  /// The discriminator that selects this schema (e.g. `'Resonance'`).
  final String type;

  /// Merge-unit name → the payload field names that move together under it.
  final Map<String, List<String>> mergeUnits;

  /// Reserved tombstone unit/field — shared with nodes so deletion has exactly
  /// one definition across the envelope (see [NodeSchema.tombstoneUnit]).
  static const String tombstoneUnit = NodeSchema.tombstoneUnit;
  static const String tombstoneField = NodeSchema.tombstoneField;
}

/// A directed edge in the collaborative graph — the same CRDT envelope as
/// [GraphNode], plus two immutable endpoints.
///
/// [fromId]/[toId] are *identity*, exactly like [id]/[type]: never stamped,
/// never merged. An edge does not "move" — re-pointing an endpoint is
/// delete (tombstone) + recreate under a new [id], matching tldraw `TLBinding`
/// semantics. [mergeEdges] asserts the endpoints match, so the merge core never
/// has to reason about a concurrent endpoint change.
class GraphEdge {
  const GraphEdge({
    required this.id,
    required this.type,
    required this.fromId,
    required this.toId,
    required this.payload,
    required this.stamps,
  });

  factory GraphEdge.fromJson(Map<String, dynamic> json) => GraphEdge(
        id: json['id'] as String,
        type: json['type'] as String,
        fromId: json['fromId'] as String,
        toId: json['toId'] as String,
        payload: Map<String, Object?>.from(json['payload'] as Map),
        stamps: (json['stamps'] as Map).map(
          (k, v) => MapEntry(
            k as String,
            FieldStamp.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        ),
      );

  /// Stable identity; immutable, never stamped, never merged.
  final String id;

  /// Discriminator selecting the app [EdgeSchema]; immutable.
  final String type;

  /// Source endpoint node id; immutable identity, never stamped, never merged.
  final String fromId;

  /// Target endpoint node id; immutable identity, never stamped, never merged.
  final String toId;

  /// Field name → value. Schema-agnostic: the engine never interprets these.
  final Map<String, Object?> payload;

  /// Merge-unit name → CRDT stamp.
  final Map<String, FieldStamp> stamps;

  /// True if a winning [EdgeSchema.tombstoneUnit] stamp marks this deleted.
  bool get isDeleted => payload[EdgeSchema.tombstoneField] == true;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'fromId': fromId,
        'toId': toId,
        'payload': payload,
        'stamps': stamps.map((k, v) => MapEntry(k, v.toJson())),
      };
}

/// Merges two replicas of the same edge ([local].id == [remote].id) under
/// [schema], producing the convergent result.
///
/// Mirrors [mergeNodes] and shares its [_mergeUnits] core — the LWW semantics
/// are identical. The one edge-specific rule: endpoints are immutable identity,
/// so merging two edges with the same [GraphEdge.id] but different endpoints is
/// a bug (a "moved" edge is delete+recreate, never a re-point). The assert
/// enforces it in debug/test builds.
GraphEdge mergeEdges(GraphEdge local, GraphEdge remote, EdgeSchema schema) {
  assert(local.id == remote.id, 'cannot merge distinct edges');
  assert(
    local.fromId == remote.fromId && local.toId == remote.toId,
    'edge endpoints are immutable identity — a moved edge is delete+recreate',
  );

  final (payload, stamps) = _mergeUnits(
    localPayload: local.payload,
    localStamps: local.stamps,
    remotePayload: remote.payload,
    remoteStamps: remote.stamps,
    fieldsOf: {
      ...schema.mergeUnits,
      EdgeSchema.tombstoneUnit: const [EdgeSchema.tombstoneField],
    },
  );

  return GraphEdge(
    id: local.id,
    type: local.type,
    fromId: local.fromId,
    toId: local.toId,
    payload: payload,
    stamps: stamps,
  );
}
