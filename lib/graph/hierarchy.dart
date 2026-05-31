/// Read-side helpers for the child→parent containment model
/// ([concept_container_via_child_pointer]).
///
/// These are pure projections — no state of their own, no caches. Callers
/// decide whether to memoize. Keep this file small and obvious; the merge
/// machinery lives in `graph_envelope.dart`, the unit names in
/// `container_schema.dart`.
///
/// **Dangling children** (decision per task #13 brief): when a parent is
/// deleted (tombstoned) or absent from the replica, its children's `parentId`
/// is *not* auto-rewritten. The merge math has no defensible "correct new
/// parent" choice across replicas. Instead, the view helpers here resolve
/// dangling parents as if the child were a root-level node — [parentOf]
/// returns null for them, and [children] of root includes them. The dangling
/// pointer is preserved in the payload so a future un-delete (resurrection
/// via tombstone LWW) re-attaches the child automatically.
library;

import 'container_schema.dart';
import 'graph_envelope.dart';

/// Returns [node]'s parent looked up in [byId], or null if the node is root
/// OR its parentId points at a missing / tombstoned node ("dangling").
GraphNode? parentOf(GraphNode node, Map<String, GraphNode> byId) {
  final pid = parentIdOf(node);
  if (pid == null) return null;
  final parent = byId[pid];
  if (parent == null || parent.isDeleted) return null; // dangling
  return parent;
}

/// Returns the children of [parent] from [all], in z-order (lex-compare on
/// fractional zIndex; missing zIndex sorts before any string so unordered
/// inserts cluster at the start in a stable position).
///
/// Tombstoned children are filtered out. O(n) scan plus an O(k log k) sort
/// where k = #children. Cache externally if you call this in a hot loop.
Iterable<GraphNode> children(GraphNode parent, Iterable<GraphNode> all) {
  final out = <GraphNode>[];
  for (final n in all) {
    if (n.isDeleted) continue;
    if (parentIdOf(n) == parent.id) out.add(n);
  }
  out.sort(_byZIndex);
  return out;
}

/// Root-level nodes from [all]: those whose [parentIdOf] is null OR points at
/// a deleted/missing parent (dangling — resolved as root per the file-level
/// doc). Sorted by z-index for render order.
Iterable<GraphNode> roots(Iterable<GraphNode> all) {
  final byId = <String, GraphNode>{for (final n in all) n.id: n};
  final out = <GraphNode>[];
  for (final n in all) {
    if (n.isDeleted) continue;
    final pid = parentIdOf(n);
    if (pid == null) {
      out.add(n);
    } else {
      final p = byId[pid];
      if (p == null || p.isDeleted) out.add(n); // dangling → root
    }
  }
  out.sort(_byZIndex);
  return out;
}

/// All transitive descendants of [parent] in [all], depth-first, each level
/// in z-order. Excludes [parent] itself. Tombstoned subtrees are skipped.
Iterable<GraphNode> descendants(
  GraphNode parent,
  Iterable<GraphNode> all,
) sync* {
  // Materialize once so the recursive walk doesn't re-iterate a generator.
  final list = List<GraphNode>.unmodifiable(all);
  for (final c in children(parent, list)) {
    yield c;
    yield* descendants(c, list);
  }
}

/// Walks parent pointers from [node] up to root. Stops at null OR at the
/// first missing/tombstoned ancestor (dangling — treated as root). Excludes
/// [node] itself. Cycle-safe: a malformed cycle terminates after at most
/// [byId].length steps.
Iterable<GraphNode> ancestors(
  GraphNode node,
  Map<String, GraphNode> byId,
) sync* {
  final seen = <String>{node.id};
  var current = parentOf(node, byId);
  while (current != null && seen.add(current.id)) {
    yield current;
    current = parentOf(current, byId);
  }
}

/// True if making [newParent] the parent of [child] would create a cycle
/// (i.e. [newParent] is already a descendant of [child], or equals [child]).
///
/// Call this before issuing a reparent write. The CRDT layer will still
/// accept a cycle-creating write if a concurrent move sneaks it in — that's
/// the trade for being commutative — but rendering can detect the cycle the
/// same way (call [ancestors] on each suspect node, look for the loop) and
/// fall the affected subtree back to root. Cycle detection at write-time is
/// the cheap defence; cycle tolerance at read-time is the safety net.
bool wouldCreateCycle(
  String child,
  String newParent,
  Map<String, GraphNode> byId,
) {
  if (child == newParent) return true;
  // Walk newParent's ancestors. If we hit `child`, a cycle would form.
  final start = byId[newParent];
  if (start == null) return false; // moving under a missing parent is not a cycle
  final seen = <String>{newParent};
  var cur = parentOf(start, byId);
  while (cur != null) {
    if (cur.id == child) return true;
    if (!seen.add(cur.id)) return true; // pre-existing cycle in the graph
    cur = parentOf(cur, byId);
  }
  return false;
}

int _byZIndex(GraphNode a, GraphNode b) {
  final za = zIndexOf(a);
  final zb = zIndexOf(b);
  // Missing zIndex sorts before any present one (stable "front of pack").
  if (za == null && zb == null) return a.id.compareTo(b.id);
  if (za == null) return -1;
  if (zb == null) return 1;
  final cmp = za.compareTo(zb);
  if (cmp != 0) return cmp;
  // Tiebreak by id for total order.
  return a.id.compareTo(b.id);
}
