# RESEARCH — type-aware read path

*Heat phase. Mostly internal ground truth (this is an architecture problem with a
complete ADR); bounded external scan noted at the end. Heat = **focused**, not a
web fan-out — the constraints live in the repo, not the literature.*

## 1. The pipeline is ClassBox-shaped end to end (verified by reading)

| Stage | File:line | Current shape | Hardwired to ClassBox? |
|---|---|---|---|
| Read doc → node | `firestore_backend.dart:164` (`_readGraphNodeFromDoc`) | builds `GraphNode(type:'ClassBox')` | **yes** (lines 176, 187) |
| Merge (absorb) | `firestore_backend.dart:144` | `mergeNodes(existing, incoming, classBoxSchema)` | **yes** |
| Merge (write, no base) | `:346` | `mergeNodes(localExisting, incoming, classBoxSchema)` | **yes** |
| Merge (write, tx base) | `:383` | `mergeNodes(remoteNode, incoming, classBoxSchema)` | **yes** |
| Validate/quarantine door | `:213` (`_tryReadValidNode`) | dry-runs `graphNodeToClassBox` | **yes** (line 248) |
| Project → store | `:287` (`_emitProjection`) | `graphNodeToClassBox(n)` per node | **yes** |
| Store field | `app_state.dart:23` | `IList<ClassBox> classBoxes` (freezed) | **yes** |
| Action | `store_class_boxes_action.dart` | `StoreClassBoxesAction(IList<ClassBox>)` | **yes** |
| Paint | `drawing_canvas.dart:96` (`ShapePainter`) | `for (box in _boxes) drawClassBox(...)` | **yes** |

**Consequence:** a Person/Repo doc written by the ingest tool would (a) read as
`type:'ClassBox'`, (b) merge under `classBoxSchema` — which has units
`geometry/label/staticMethods/...`, NOT `profile/meta/curation` — so its
agent-owned `profile`/`meta` stamps map to **no known unit**, and (c)
`graphNodeToClassBox` would read its geometry fields fine but drop `login`,
`avatarUrl`, `commits`, `kind` on the floor (they aren't ClassBox fields).

### The critical merge subtlety (settles the falsifier, partially)

`mergeNodes` fails **closed** (`StateError`) when `schema.type != local.type`
(`graph_envelope.dart` merge guard). BUT today the read path **constructs** every
node as `type:'ClassBox'` (line 176/187), so `local.type` is *always* `'ClassBox'`
and the guard never fires — the type mismatch is masked by the hardwired
constructor, not caught. A Person doc doesn't get quarantined by a type check; it
gets **silently mis-merged** under the wrong schema and then partially dropped at
projection. So the consolidation's phrase "silently quarantined" is *imprecise*:
the real failure is **silent field loss under a wrong schema**, which is worse
than a clean quarantine (no breadcrumb fires). **This is a Heat finding that
sharpens the problem statement** — the registry isn't just "render nicely", it's
"stop merging Person facts under ClassBox units where they vanish".

`_mergeUnits` (graph_envelope.dart) only copies payload fields for units present
in `fieldsOf`; a stamp for an unknown unit "advances without moving its fields"
(documented in the mergeEdges comment). So Person `profile` stamps would advance
HLC but never carry `login`/`avatarUrl`. Confirmed: **field loss, not quarantine.**

## 2. Edges: envelope complete, sync path absent

- `GraphEdge`/`EdgeSchema`/`mergeEdges` shipped PR #9, fully tested. Identity =
  `(id, type, fromId, toId)`, all immutable; a "moved" edge is delete+recreate.
- `_absorbRemoteSnapshot` **early-returns** unless `section == SyncSection.classBoxes`
  (line 101). `SyncSection` = `{profile, classBoxes}` only — **no edge section**.
- No edge collection, no edge in `AppState`, no edge in any painter.
- ADR-0003 edge: `contribution` (Person→Repo), `id="contrib:<personId>:<repoId>"`,
  single agent-owned `weight` unit (`commits`).

**Implication:** the edge vertical is *new construction* (collection + sync section
+ absorb branch + store field + painter), not a generalization of the node path.
It shares the `_mergeUnits` core and the DoS-door *pattern* but needs its own door
(the existing door's comment explicitly says "an edge sync path, when it exists,
needs its own equivalent door").

## 3. What the ingest tool writes today (stepping stone)

`tool/community_ingest.dart` + `lib/graph/community_projection.dart` project the
org into **`ClassBox`-shaped** docs (geometry + name) in the `domain-objects`
collection — deliberately, so it renders through the proven path TODAY
(ADR-0003 "Person-as-ClassBox stepping stone"). `agent_draw_envelope.dart`'s
`agentLabelUpdateDoc` already does masked updates on the agent-owned `label` unit
only, preserving human geometry — the authority-partition write discipline is
**already implemented** for the stepping stone and generalizes cleanly to
`profile`/`meta`.

## 4. The DoS boundary (must stay sealed — PR #13, 6-round cage-match)

Invariant: **one malformed/hostile remote doc → per-doc skip + breadcrumb, never
a throw that sinks the batch to ProblemPage.** Enforced by: (a) `_tryReadValidNode`
door removing every known throw source; (b) a try/quarantine wrapping the whole
absorb-loop body; (c) `_emitProjection`'s per-node fail-closed. Generalizing the
merge to a registry **re-opens this exact boundary** because a new degenerate
state appears: **type present but unregistered**. The door currently dry-runs
`graphNodeToClassBox`; a registry means the dry-run must dispatch on type, and an
unknown type must quarantine (skip+breadcrumb), never throw.

## 5. Bounded external scan (low yield — as expected for an internal problem)

- **Typed CRDT registries** (Yjs/Automerge): the standard shape is a `type`
  discriminator selecting a per-type reducer; matches `GraphNode.type` exactly.
  No novel constraint imported.
- **Directed edges on a Flutter `CustomPainter`**: anchor at each node's rect
  center, clip the segment to the rect boundary so the line touches the box edge
  not the center; arrowhead via two short segments off the direction vector.
  Variable node size (Person boxes scale with commits) means anchor = geometric
  center, endpoint = center ± (halfW,halfH) projected onto the direction. Trivial
  math, no library needed (matches existing `canvas.drawLine` usage).
- **Multi-collection Firestore snapshot sync**: independent `.snapshots()`
  listeners per collection is the documented norm; no cross-collection
  transaction needed because node and edge merges are independent. Confirms the
  edge section can be a sibling listener, not a rework of the node one.

**Heat verdict:** the metal is mostly internal and already well-separated. The
one thing Heat *changed*: the failure mode is **silent field loss under a wrong
schema**, not a clean quarantine — which strengthens (not weakens) the case that a
real registry is needed on the read side, partially answering CRUCIBLE's
falsifier. The remaining open question for Fold/Temper: **is the render-only
`kind`-discriminator shortcut viable given that field loss, or does correct
merging force the full registry?**
