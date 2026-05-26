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

/// Merges two replicas of the same node ([local].id == [remote].id) under
/// [schema], producing the convergent result.
///
/// For each merge unit present on either side, the higher-HLC stamp wins
/// ([FieldStamp.wins]); the winning side's payload fields for that unit are
/// taken. Because tombstones are just another unit, deletion/resurrection falls
/// out of the same loop. The operation is commutative, associative and
/// idempotent — re-applying any change converges to the same state, which is
/// what lets a dumb transport (Firestore, MQTT, …) deliver in any order.
GraphNode mergeNodes(GraphNode local, GraphNode remote, NodeSchema schema) {
  assert(local.id == remote.id, 'cannot merge distinct nodes');

  final units = {...local.stamps.keys, ...remote.stamps.keys};
  final mergedPayload = <String, Object?>{...local.payload};
  final mergedStamps = <String, FieldStamp>{...local.stamps};

  final fieldsOf = {
    ...schema.mergeUnits,
    NodeSchema.tombstoneUnit: const [NodeSchema.tombstoneField],
  };

  for (final unit in units) {
    final localStamp = local.stamps[unit];
    final remoteStamp = remote.stamps[unit];

    // Remote wins this unit if local has no stamp, or remote's stamp beats it.
    final remoteWins =
        remoteStamp != null && (localStamp == null || remoteStamp.wins(localStamp));
    if (!remoteWins) continue;

    mergedStamps[unit] = remoteStamp;
    for (final field in fieldsOf[unit] ?? const <String>[]) {
      mergedPayload[field] = remote.payload[field];
    }
  }

  return GraphNode(
    id: local.id,
    type: local.type,
    payload: mergedPayload,
    stamps: mergedStamps,
  );
}
