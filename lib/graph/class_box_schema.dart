import 'package:domain_visualiser/models/domain-objects/domain_object.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'container_schema.dart';
import 'graph_envelope.dart';
import 'hlc_manager.dart';

/// The merge-unit grain for a [ClassBox], in the precise shape the spec
/// declares (project_graph_engine_forward_plan, step 7).
///
/// - `geometry` groups `left/top/right/bottom` so a concurrent drag never tears
///   a box across replicas.
/// - `label` and each list move under their own unit so Alice can rename while
///   Bob drags — both edits survive.
/// - List units are LWW-whole-list for v1; OR-Set is the named first upgrade
///   (see [concept_merge_unit_grain]).
/// The ClassBox merge-unit grain, with the three universal container units
/// ([parentUnit], [containerTypeUnit], [zIndexUnit]) layered on via
/// [withContainerUnits] — that's the wiring that makes [mergeNodes] honour
/// `parentId`/`containerType`/`zIndex` stamps when syncing a real ClassBox
/// envelope. Without this, those stamps would round-trip but their payload
/// fields would never get copied across a merge boundary (P0 from cage-match
/// review of PR #7).
///
/// Cannot be `const` because [withContainerUnits] is not a const constructor
/// (it builds a non-const `Map` from `base.mergeUnits` + the three injected
/// units). `final` is fine — the schema is initialized once at app start.
final NodeSchema classBoxSchema = withContainerUnits(const NodeSchema(
  type: 'ClassBox',
  mergeUnits: {
    'geometry': ['left', 'top', 'right', 'bottom'],
    'label': ['name'],
    'staticMethods': ['staticMethods'],
    'instanceMethods': ['instanceMethods'],
    'staticVariables': ['staticVariables'],
    'instanceVariables': ['instanceVariables'],
  },
));

/// Reserved key in the Firestore document holding the CRDT envelope. Keeping
/// it under a single `__envelope__` key (rather than spraying `_geom_hlc`,
/// `_label_hlc`, … into the doc body) means the existing `toClassBox()`
/// extension keeps working unchanged on the payload fields, and a future
/// non-domvis reader can ignore or strip the envelope cleanly.
const String envelopeKey = '__envelope__';

/// Projects a [ClassBox] into a [GraphNode] **with all merge units stamped
/// fresh**. Use for a brand-new box (AddClassBox) where every unit is being
/// authored for the first time.
GraphNode classBoxToGraphNode(
  ClassBox box, {
  required HlcManager hlc,
  required String origin,
}) {
  FieldStamp stamp() => FieldStamp(hlc: hlc.issue(), origin: origin);
  return GraphNode(
    id: box.id,
    type: 'ClassBox',
    payload: _payloadOf(box),
    stamps: {
      'geometry': stamp(),
      'label': stamp(),
      'staticMethods': stamp(),
      'instanceMethods': stamp(),
      'staticVariables': stamp(),
      'instanceVariables': stamp(),
    },
  );
}

/// Projects [updated] into a [GraphNode] **stamping ONLY the merge units that
/// actually changed** vs [previous]. This is the partial-update path used by
/// UpdateDomain: if only the geometry moved, only `geometry` gets a new stamp,
/// so a concurrent rename by another peer still wins on its own unit.
///
/// If [previous] is null, all units are stamped (treated as create).
GraphNode classBoxToGraphNodePartial({
  required ClassBox updated,
  required ClassBox? previous,
  required HlcManager hlc,
  required String origin,
}) {
  if (previous == null) {
    return classBoxToGraphNode(updated, hlc: hlc, origin: origin);
  }
  FieldStamp stamp() => FieldStamp(hlc: hlc.issue(), origin: origin);
  final stamps = <String, FieldStamp>{};
  if (updated.left != previous.left ||
      updated.top != previous.top ||
      updated.right != previous.right ||
      updated.bottom != previous.bottom) {
    stamps['geometry'] = stamp();
  }
  if (updated.name != previous.name) {
    stamps['label'] = stamp();
  }
  // IList overrides == for deep value equality (fast_immutable_collections
  // ^11), so the previous hand-rolled `_iListEq` was just reinventing the
  // built-in. Direct `!=` it is.
  if (updated.staticMethods != previous.staticMethods) {
    stamps['staticMethods'] = stamp();
  }
  if (updated.instanceMethods != previous.instanceMethods) {
    stamps['instanceMethods'] = stamp();
  }
  if (updated.staticVariables != previous.staticVariables) {
    stamps['staticVariables'] = stamp();
  }
  if (updated.instanceVariables != previous.instanceVariables) {
    stamps['instanceVariables'] = stamp();
  }
  return GraphNode(
    id: updated.id,
    type: 'ClassBox',
    payload: _payloadOf(updated),
    stamps: stamps,
  );
}

/// Projects a merged [GraphNode] back to a [ClassBox] for the Redux store.
///
/// Defensive: missing payload fields fall back to the existing [base] (if
/// supplied) or to neutral defaults — a remote producer that omits a unit
/// shouldn't crash the converter.
///
/// [_payloadOf] carries the identity-adjacent fields [ClassBox.userId] and
/// [ClassBox.flightTime] alongside the mutable units. They are written once at
/// create-time and are not declared in any merge unit, so a partial-update
/// envelope (which omits them) still preserves them via the read-merge-write
/// transaction in [FirestoreBackend]: an absent field in [incoming.payload]
/// does NOT overwrite the remote field, because [mergeNodes] only copies
/// payload entries belonging to a unit whose stamp wins. Cold readers see them
/// because the doc has carried them since create.
ClassBox graphNodeToClassBox(GraphNode node, {ClassBox? base}) {
  final p = node.payload;
  return ClassBox(
    id: node.id,
    left: (p['left'] as num?)?.toDouble() ?? base?.left ?? 0.0,
    top: (p['top'] as num?)?.toDouble() ?? base?.top ?? 0.0,
    right: (p['right'] as num?)?.toDouble() ?? base?.right ?? 0.0,
    bottom: (p['bottom'] as num?)?.toDouble() ?? base?.bottom ?? 0.0,
    name: p['name'] as String? ?? base?.name,
    staticMethods: _readIList(p['staticMethods']) ?? base?.staticMethods,
    instanceMethods: _readIList(p['instanceMethods']) ?? base?.instanceMethods,
    staticVariables: _readIList(p['staticVariables']) ?? base?.staticVariables,
    instanceVariables:
        _readIList(p['instanceVariables']) ?? base?.instanceVariables,
    userId: p['userId'] as String? ?? base?.userId,
    flightTime: (p['flightTime'] as num?)?.toInt() ?? base?.flightTime,
  );
}

/// True if every stamp on [node] was minted by [origin] — i.e. this update is
/// a pure echo of writes the local client just made. Used by the snapshot
/// listener to skip re-projecting our own writes back into the store.
bool nodeIsPureEcho(GraphNode node, String origin) =>
    node.stamps.isNotEmpty &&
    node.stamps.values.every((s) => s.origin == origin);

/// Builds the schema-payload from a ClassBox. Identity-adjacent fields
/// (`userId`, `flightTime`) ride along even though they're not in any merge
/// unit — see `graphNodeToClassBox` doc for why this is safe under partial
/// updates.
Map<String, Object?> _payloadOf(ClassBox b) => {
      'left': b.left,
      'top': b.top,
      'right': b.right,
      'bottom': b.bottom,
      if (b.name != null) 'name': b.name,
      if (b.staticMethods != null)
        'staticMethods': b.staticMethods!.toList(),
      if (b.instanceMethods != null)
        'instanceMethods': b.instanceMethods!.toList(),
      if (b.staticVariables != null)
        'staticVariables': b.staticVariables!.toList(),
      if (b.instanceVariables != null)
        'instanceVariables': b.instanceVariables!.toList(),
      if (b.userId != null) 'userId': b.userId,
      if (b.flightTime != null) 'flightTime': b.flightTime,
    };

IList<String>? _readIList(Object? raw) {
  if (raw == null) return null;
  if (raw is List) return IList(raw.map((e) => e as String));
  return null;
}
