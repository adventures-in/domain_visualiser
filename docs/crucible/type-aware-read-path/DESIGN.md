# DESIGN — type-aware read path (#2432 / #22)

*Cast phase. The mold. Placed for Temper to strike alongside CRUCIBLE.md +
RESEARCH.md.*

## Problem (sharpened by Heat)

`FirestoreBackend` reads, merges, and projects every doc as `type:'ClassBox'`
under `classBoxSchema` (5 hardwired sites + the store/painter). A Person/Repo doc
written per ADR-0003 does not get cleanly quarantined — it gets **silently
mis-merged under the wrong schema and its agent-owned fields
(`login`/`avatarUrl`/`commits`/`kind`) vanish** (`_mergeUnits` only carries fields
of *known* units). Edges have a finished envelope (`GraphEdge`, PR #9) but **no
sync path at all**. Goal: the 16 community docs render as distinct typed
Person/Repo nodes joined by `contribution` edges on the live canvas — without
breaking the PR#13 DoS boundary.

## Shape

### The one atypical element (the load-bearing elegance)

**The type discriminator lives IN the CRDT envelope, and its ABSENCE means
`ClassBox`.** Wire docs declare `_envelope.type` (single-underscore, reserved-name
safe). The registry's lookup for a missing/unknown-at-read type defaults to
`classBox`. Consequence: **every existing prod doc and every future human-drawn
box needs zero migration** — backward compatibility falls out of the default
branch, not a data migration. This is what lets Slice 0 be a provably
zero-behavior-change refactor.

### Core interfaces

```dart
// lib/graph/schema_registry.dart  (new — the single source of truth)
class SchemaRegistry {
  const SchemaRegistry(this._nodes, this._edges);
  final Map<String, NodeSchema> _nodes;
  final Map<String, EdgeSchema> _edges;

  /// Absent/unknown type → the ClassBox default (backward compat + fail-soft).
  NodeSchema nodeSchemaFor(String type) => _nodes[type] ?? classBoxSchema;
  EdgeSchema edgeSchemaFor(String type) => _edges[type] ?? contributionSchema;
  bool hasNodeType(String type) => _nodes.containsKey(type);
}

final defaultRegistry = SchemaRegistry(
  { 'ClassBox': classBoxSchema, 'Person': personSchema, 'Repo': repoSchema },
  { 'contribution': contributionSchema },
);
```

Schemas from ADR-0003 (authority-partitioned units):

```dart
// personSchema: profile[login,name,avatarUrl,htmlUrl,kind] (agent) +
//               geometry[left,top,right,bottom] (human) +
//               curation[displayLabel,hidden,pinned] (human)
// repoSchema:   meta[name,fullName,description,htmlUrl,pushedAt] (agent) + geometry + curation
// contributionSchema (edge): weight[commits] (agent)
```

### Read-path dispatch (the merge-core generalization)

- `_readGraphNodeFromDoc` reads `_envelope['type']` → `node.type` (default
  `'ClassBox'` when absent). This is the ONLY behavioral change in Slice 0, and it
  is a no-op for every current doc (none carry `_envelope.type`).
- The 3 merge sites call `mergeNodes(a, b, registry.nodeSchemaFor(a.type))`.
  Because `a.type` now flows from the wire, `mergeNodes`' existing
  `schema.type != local.type` fail-closed guard becomes *live* — a Person doc
  merges under `personSchema`, and a corrupt/forged type mismatch fails closed
  into the existing per-doc quarantine (not the batch).
- **New degenerate state → DoS door update:** `_tryReadValidNode` must dry-run
  the *type-appropriate* projection. Unknown-but-present type → quarantine
  (skip+breadcrumb), never throw. `_emitProjection` dispatches projection by type,
  keeping its per-node fail-closed backstop.

### Projection + store

Project each `GraphNode` to a lightweight `CanvasNode` view (a sealed/`freezed`
sum: `PersonNode | RepoNode | ClassBoxNode`) carrying only what the painter needs.
`AppState` gains `IList<CanvasNode> nodes` and `IList<CanvasEdge> edges`
(additive; existing `classBoxes` stays until Slice 4 retires it, so no big-bang
store rewrite). Painter dispatches on the node variant.

### Edge vertical (new construction, shares the merge core + door PATTERN)

`SyncSection.edges` + an `edges` collection + a sibling `.snapshots()` listener +
an edge absorb branch with **its own** `_tryReadValidEdge` door (the node door's
comment already anticipates this) + `contributionSchema` + `IList<CanvasEdge>` +
painter draws each edge as a line clipped to the endpoint rects (anchor = center,
endpoint = center projected to rect boundary; variable Person size handled by the
projection math — RESEARCH §5).

## Build order (core-first, each step independently useful, no big-bang)

- **Slice 0 — registry refactor, ZERO behavior change (cage-match tier).**
  Introduce `SchemaRegistry` with ClassBox the only registered node type; route
  the 3 merge sites + door through it; `_readGraphNodeFromDoc` reads
  `_envelope.type` defaulting to ClassBox. All 116 tests green, byte-identical
  behavior. Independently useful: unblocks everything, reviewable alone. **RED
  proof:** a test doc carrying `_envelope.type:'Person'` with an unregistered
  schema must quarantine cleanly (breadcrumb, no throw, batch survives).
- **Slice 1 — typed nodes read + projected (still box-rendered).** Register
  `personSchema`/`repoSchema`; project to `PersonNode`/`RepoNode` carrying real
  fields. Person facts stop vanishing. Independently useful even before pretty
  rendering.
- **Slice 2 — edge vertical.** New sync section + door + `contributionSchema` +
  store + painter lines. Edges render. Independently useful.
- **Slice 3 — flip the producer.** `community_ingest.dart` writes typed
  Person/Repo + contribution edges instead of the ClassBox stepping stone.
  Requires the reader (0–2) live. Done-condition candidate.
- **Slice 4 — visual distinction + retire stepping stone.** Person vs Repo visual
  forms, size-by-commits, remove the ClassBox-reuse projection. Demo polish.

## Blast radius + consent spine (cage before monster)

- **Trust boundary re-opened** (read/merge core) → **cage-match by law**, every
  slice touching it. Owner: me (author) + cross-family adversary.
- **Injection surface:** unchanged shape — untrusted remote docs; the new attack
  is a **forged/unknown `_envelope.type`**. Mitigation IN the design: unknown type
  → quarantine at the door; type present but mismatched vs id-derived expectation
  is *not* trusted (id prefix is advisory, the envelope type is authoritative but
  still must project-or-quarantine).
- **All local/undeployed until Slice 3 + deploy.** No new public endpoint.
- **The one outward-facing action:** re-running `community_ingest` against prod
  Firestore (Slice 3). Already-authorized pattern (PR #16), idempotent (totals not
  deltas per ADR-0003 Decision 2), gated behind the agent OAuth owner token.
  Demo write = a re-run of an existing, consented tool. Draft-and-show before the
  prod write, per standing rules.

## Claims to falsify (hand these to the adversary)

1. **The registry is load-bearing on READ, not just render.** Heat found the
   failure is silent field loss under `classBoxSchema`, so correct *merging* (not
   just drawing) needs the type. Falsifier: if a `kind`-tagged ClassBox projection
   could carry `login`/`commits` without a per-type schema, the registry is
   over-built. (Rebuttal in hand: ClassBox has no such fields and its units don't
   match; but strike it.)
2. **Absence-means-ClassBox is safe backward compat.** Assumes no existing prod
   doc carries `_envelope.type`. Falsifier: any doc already does → Slice 0 is not
   zero-behavior. (Mitigation: grep prod / assert in the acceptance test.)
3. **Edge sync can be a sibling listener with no cross-collection ordering.**
   Assumes a `contribution` edge referencing a not-yet-arrived Person node renders
   gracefully (dangling edge). Falsifier: painter throws on a missing endpoint →
   DoS. (Mitigation: edge painter skips edges with an unresolved endpoint; that's
   a *visibility-consistency across paired reads* invariant — enumerate it.)
4. **The id-scheme mismatch is handled.** Stepping stone writes
   `gh-person-<id>`/`gh-repo-<id>`; ADR-0003 says `gh:<id>`/`repo:<id>`. Flipping
   the producer with new ids **duplicates every node** unless old ids are reused or
   tombstoned. Falsifier: Slice 3 doubles the graph. (This is the biggest open
   variable — see below.)
5. **The DoS boundary stays sealed through a registry dispatch.** Adding a
   type-dispatched projection to the door adds a code path; a new throw source in
   an unregistered-type branch could sink the batch. Falsifier: a crafted unknown
   type throws past the door.

## Rejected alternatives

- **`kind`-discriminator on ClassBox, no registry (the shortcut).** Rejected:
  ClassBox can't hold agent-owned Person/Repo fields, and its merge units don't
  match ADR-0003's authority partition — Person facts would still vanish on merge.
  Render-only tagging doesn't fix the *merge*. (But this is claim-to-falsify #1 —
  let the adversary retry it.)
- **Derive type from id prefix (`gh:`→Person).** Rejected as *authoritative*
  source: id prefix is advisory only; a hostile doc could carry a `gh:` id with
  ClassBox geometry. Envelope type is authoritative, id prefix at most a
  cross-check. (Keeps identity and type as separate concerns.)
- **Big-bang store rewrite (`classBoxes` → `nodes` in one PR).** Rejected:
  couples the merge-core change to a freezed/reducer/painter rewrite, making the
  cage-match surface enormous. Additive `nodes`/`edges` fields let Slice 0 be
  provably behavior-neutral.
- **One shared DoS door for nodes AND edges.** Rejected: node and edge validation
  differ (edges have the immutable `(from,to)` identity tuple + endpoint
  resolution); the node door's own comment says edges need their own door.

## Fold (author self-pass — findings folded back in)

- **[FOLD-1, structural] Absent vs present-but-unregistered type must NOT
  collapse.** The Shape's `nodeSchemaFor(t) => _nodes[t] ?? classBoxSchema`
  defaults BOTH an absent type and an unknown-present type to ClassBox — which
  silently mis-merges a future `'Comment'` doc under ClassBox instead of skipping
  it, leaking the DoS boundary through the registry. **Fix (folded):** the
  *reader* distinguishes them, not the registry lookup:
  - `_envelope.type` **absent** → `type = 'ClassBox'` (backward compat; a
    registered type — merges normally).
  - `_envelope.type` **present + registered** → that schema.
  - `_envelope.type` **present + NOT registered** → the door quarantines
    (skip+breadcrumb, never throw). This is *also* forward-compat: an older client
    skips a newer node kind gracefully.
  So `_readGraphNodeFromDoc` sets type from the wire (default ClassBox when
  absent); `_tryReadValidNode` checks `registry.hasNodeType(node.type)` and
  quarantines an unregistered present type BEFORE the projection dry-run.
  `nodeSchemaFor` still defaults to classBoxSchema, but it is only ever reached
  for a type the door already admitted. Verified: no current writer emits a type
  field (grep of all 3 writers), so the "absent → ClassBox" branch covers 100% of
  today's docs — Slice 0 stays provably behavior-neutral.
- **[FOLD-2] A tombstoned endpoint is also an unresolved endpoint.** OPEN-3's
  dangling-edge skip must treat `endpoint.isDeleted == true` the same as
  endpoint-absent — otherwise an edge to a just-deleted node draws a line to a
  ghost. Fold into the edge painter's resolve check: render iff both endpoints
  exist AND neither is deleted. (Visibility-consistency across paired reads: the
  node set and edge set share one converged view; the edge painter applies the
  same isDeleted predicate the node painter does.)
- **[FOLD-3] Claim #2 discharged, claim #4 confirmed live.** No writer emits a
  wire type (backward compat safe). The id drift is real and shipped — OPEN-1 is
  load-bearing, not hypothetical.

## Open variables (named, not skated)

- **[OPEN-1] Id-scheme migration.** Reuse existing `gh-person-<id>` ids in the
  typed schema (violates ADR-0003's `gh:<id>` form but avoids duplication), OR
  tombstone the 16 stepping-stone docs and re-create under `gh:<id>` (clean but a
  destructive prod write on the demo canvas). **Leaning: reuse the existing ids
  and amend ADR-0003's id form to what shipped** (hyphen not colon — colon is also
  fine as a Firestore doc id, but the stepping stone already chose hyphen). Decide
  before Slice 3. This is the single most likely thing to bite the demo.
- **[OPEN-2] Does `_envelope.type` belong inside the stamps envelope or as a
  sibling reserved `_type` field?** Leaning: sibling `_type` (envelope stays
  purely `{stamps:...}`; type is identity-adjacent like `id`, not CRDT metadata).
- **[OPEN-3] Dangling-edge render policy** (endpoint not yet arrived): skip vs
  ghost. Leaning: skip (safest for DoS), revisit for liveliness.
- **[OPEN-4] CanvasNode/CanvasEdge as freezed sum vs plain sealed classes** —
  ergonomics only, no correctness weight.
