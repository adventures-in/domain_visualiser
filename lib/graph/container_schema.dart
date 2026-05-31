/// Container/hierarchy increment for the graph envelope (task #13).
///
/// **Design call** (see [concept_container_via_child_pointer]): containment is
/// expressed as a **child→parent pointer + membership tag** on every node, NOT
/// as a `children` list on the parent. Excalidraw's shape, not Penpot's. The
/// CRDT correctness argument:
///
/// - Reparenting a node is ONE write to ONE merge unit (`parent`). Two peers
///   moving the same child to different parents concurrently → LWW on `parent`
///   picks one winner. No `oldParent.children` / `newParent.children` /
///   `child.parentId` triple-write that has to stay consistent.
/// - Re-ordering siblings is ONE write to ONE merge unit (`zIndex`) on the
///   moved node. A fractional-index string keeps siblings totally ordered
///   without anyone owning a `children` vector.
///
/// **No schema-type change to [GraphNode]**. The three units are optional
/// payload fields. They live here as a convention — registered on every
/// [NodeSchema] via [withContainerUnits] — so the engine's [mergeNodes] honours
/// them the same way it honours app-declared units.
library;

import 'graph_envelope.dart';

/// Merge-unit name carrying the child→parent pointer. Payload key
/// [parentField]. Absent / null = root-level node.
const String parentUnit = 'parent';
const String parentField = 'parentId';

/// Merge-unit name carrying the container discriminator. Payload key
/// [containerTypeField]. Absent / null = leaf (cannot contain children).
/// Allowed values: `'group'`, `'frame'`. We don't enforce the enum at the
/// envelope layer — apps that don't care simply omit it.
const String containerTypeUnit = 'containerType';
const String containerTypeField = 'containerType';

/// Merge-unit name carrying the sibling z-order key. Payload key
/// [zIndexField]. A fractional-index string (see `fractional_index.dart`).
/// Two siblings order by lex-compare of their zIndex strings.
const String zIndexUnit = 'zIndex';
const String zIndexField = 'zIndex';

/// Returns a [NodeSchema] equivalent to [base] but with the three universal
/// container units ([parentUnit], [containerTypeUnit], [zIndexUnit]) layered
/// in. Apps don't need to remember to add them — every node has a position in
/// the hierarchy (even if that position is "root, no order specified").
///
/// If [base] already declares any of the three units (custom grain), the
/// caller's declaration wins — we only fill in what's missing.
NodeSchema withContainerUnits(NodeSchema base) {
  final merged = <String, List<String>>{...base.mergeUnits};
  merged.putIfAbsent(parentUnit, () => const [parentField]);
  merged.putIfAbsent(containerTypeUnit, () => const [containerTypeField]);
  merged.putIfAbsent(zIndexUnit, () => const [zIndexField]);
  return NodeSchema(type: base.type, mergeUnits: merged);
}

/// Convenience reader: the node's parent pointer (or null for root).
String? parentIdOf(GraphNode node) => node.payload[parentField] as String?;

/// Convenience reader: the container discriminator (or null for leaves).
String? containerTypeOf(GraphNode node) =>
    node.payload[containerTypeField] as String?;

/// Convenience reader: the node's z-order key (or null if it was never set —
/// treat as "no specified order" at the render layer).
String? zIndexOf(GraphNode node) => node.payload[zIndexField] as String?;

/// True if [node] is a container (group or frame). Convenience predicate; apps
/// can also peek at [containerTypeOf] directly.
bool isContainer(GraphNode node) => containerTypeOf(node) != null;
