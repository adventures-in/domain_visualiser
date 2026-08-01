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
`ClassBox`.** Wire docs declare `_type` (single-underscore, reserved-name
safe). The registry's lookup for a missing/unknown-at-read type defaults to
`classBox`. Consequence: **every existing prod doc and every future human-drawn
box needs zero migration** — backward compatibility falls out of the default
branch, not a data migration. This is what lets Slice 0 be a provably
zero-behavior-change refactor.

### Core interfaces

```dart
// lib/graph/schema_registry.dart  (new — the single source of truth)
//
// TEMPER-REVISED (Carnot+Tesla consensus, findings T1/T2): the registry lookup is
// TOTAL OVER REGISTERED TYPES ONLY. There is NO public unknown→ClassBox (or
// unknown→contribution) fallback — that was "guard the window", a collapse any
// call site past the door could silently reopen. Absence-means-ClassBox lives in
// EXACTLY ONE place: the reader (_readGraphNodeFromDoc), which stamps the type
// 'ClassBox' onto a doc that carries no _type. By the time any code asks the
// registry for a schema, the type is a concrete admitted string.
class SchemaRegistry {
  const SchemaRegistry(this._nodes, this._edges);
  final Map<String, NodeSchema> _nodes;
  final Map<String, EdgeSchema> _edges;

  /// Null iff [type] is not registered — callers MUST treat null as "quarantine",
  /// never substitute a default. (The door checks this before any merge/project.)
  NodeSchema? nodeSchemaFor(String type) => _nodes[type];
  EdgeSchema? edgeSchemaFor(String type) => _edges[type];
  bool hasNodeType(String type) => _nodes.containsKey(type);
  bool hasEdgeType(String type) => _edges.containsKey(type);
}

// ClassBox is registered like any other type — the reader's absence-default names
// it explicitly, the registry does not privilege it. Edges have NO default: there
// are zero legacy edge docs, so an absent/unknown edge type is always a quarantine.
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

- `_readGraphNodeFromDoc` reads the sibling `_type` field → `node.type` (default
  `'ClassBox'` when absent). This is the ONLY behavioral change in Slice 0, and it
  is a no-op for every current doc (none carry `_type`).
- The 3 merge sites call `mergeNodes(a, b, registry.nodeSchemaFor(a.type))`.
  Because `a.type` now flows from the wire, `mergeNodes`' existing
  `schema.type != local.type` fail-closed guard becomes *live* — a Person doc
  merges under `personSchema`, and a corrupt/forged type mismatch fails closed
  into the existing per-doc quarantine (not the batch).
- **The one-way upgrade rule (normative — resolves the migration/forgery
  collision).** A type mismatch on the same id is NOT uniformly hostile. Exactly
  one transition is a legitimate migration: **local type is the absent-default
  `ClassBox` AND the incoming doc carries an explicit `_type`.** The absent-default
  is the only upgradeable type precisely because it was never *declared* — nothing
  was asserted to contradict. So the merge sites apply:
  - `local.type == 'ClassBox'` (absent-default) **and** `incoming.type` is an
    explicit registered type → **adopt `incoming.type`**: re-key the local node's
    type and merge under the incoming schema. The human-owned `geometry` unit is
    a *separate merge unit*, so the drag survives the upgrade untouched (this is
    the ADR-0003 authority partition paying off — geometry is not coupled to the
    agent-owned typed units). One-way only: an upgraded node's type is now explicit
    and can never be re-flipped.
  - `local.type` is any *explicit* type and `incoming.type` differs (Person→Repo,
    Person→ClassBox-explicit, …) → **hostile → quarantine** (the existing
    `mergeNodes` StateError, caught per-doc).
  This distinguishes migration from forgery by the asymmetry of *declared vs
  defaulted*, with no separate trust flag. The RED proof set covers both arms:
  ClassBox→Person accepts + preserves geometry; Person→Repo quarantines.
- **New degenerate state → DoS door update:** `_tryReadValidNode` must dry-run
  the *type-appropriate* projection. Unknown-but-present type → quarantine
  (skip+breadcrumb), never throw. `_emitProjection` dispatches projection by type,
  keeping its per-node fail-closed backstop. **Bounded telemetry (part of the DoS
  boundary):** quarantine breadcrumbs coalesce by `(failure-class, time-window)`
  so a hostile collection of thousands of unknown-type docs cannot turn a no-throw
  boundary into unbounded log churn.

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

**Atomic publish model (normative — the two-listener commit contract).** The node
and edge listeners are independent, but the store sees ONE converged view. Each
absorb runs validate→merge→project on a *candidate*, then atomically publishes the
accepted `(nodes, edges)` snapshot; on a per-doc failure it preserves the previous
accepted snapshot for that doc (retain-last-good) and quarantines only the failed
candidate — a projector failure for one type never poisons the prior good
projection, and edges never paint against a half-updated node map. Endpoint
resolution is at **emit/paint time** over the current joined view (skip an edge iff
an endpoint is absent OR tombstoned), never an absorb-time drop keyed on listener
arrival order.

## Build order (core-first, each step independently useful, no big-bang)

- **Slice 0 — registry refactor, ZERO behavior change (cage-match tier).**
  Introduce `SchemaRegistry` with ClassBox the only registered node type; route
  the 3 merge sites + door through it; `_readGraphNodeFromDoc` reads
  `_type` defaulting to ClassBox. All 116 tests green, byte-identical
  behavior. Independently useful: unblocks everything, reviewable alone. **RED
  proof:** a test doc carrying `_type:'Person'` with an unregistered
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
  is a **forged/unknown `_type`**. Mitigation IN the design: unknown type
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
   doc carries `_type`. Falsifier: any doc already does → Slice 0 is not
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
  - `_type` **absent** → `type = 'ClassBox'` (backward compat; a
    registered type — merges normally).
  - `_type` **present + registered** → that schema.
  - `_type` **present + NOT registered** → the door quarantines
    (skip+breadcrumb, never throw). This is *also* forward-compat: an older client
    skips a newer node kind gracefully.
  So `_readGraphNodeFromDoc` sets type from the wire (default ClassBox when
  absent); `_tryReadValidNode` checks `registry.hasNodeType(node.type)` and
  quarantines an unregistered present type BEFORE the projection dry-run.
  `nodeSchemaFor` returns `NodeSchema?` and is null for an unadmitted type — see
  the Temper revision (T1): the registry has **no** ClassBox fallback; absence is
  resolved only in the reader. Verified: no current writer emits a type field
  (grep of all 3 writers), so the "absent → ClassBox" branch covers 100% of
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

- **[OPEN-1 → HARD GATE before Slice 3] Id-scheme migration.** *Elevated from
  "open lean" to a blocking gate by Carnot+Tesla consensus — Slice 3 is NOT a
  done-condition while this is undecided.* Blast radius is larger than "duplicate
  every node" (Tesla): the id is the CRDT document's identity, so it also
  **triples** into `contrib:<personId>:<repoId>` edge ids, and a tombstone+recreate
  under a new scheme **destroys human-owned geometry** on the demo canvas (ingest
  writes agent totals, it does not restore peer geometry edits). Decide via this
  matrix, before any Slice-3 prod write:

  | option | node dup? | edge id impact | human geometry | verdict |
  |---|---|---|---|---|
  | **reuse shipped `gh-person-<id>`, amend ADR-0003 + one-way upgrade** | none | edge id derives from existing ids, consistent | preserved (upgrade rule) | **CHOSEN** |
  | migrate → `gh:<id>`, tombstone old | none (old tombstoned) | edges must re-derive under new ids | **DESTROYED** (re-create loses geometry unit) | rejected for the demo |
  | dual-write both id forms | **doubles** | ambiguous | split | forbidden |

  **Resolution (chosen):** reuse the shipped `gh-person-<id>`/`gh-repo-<id>` node
  ids; the same-id ClassBox→typed transition is handled by the **one-way upgrade
  rule** (read-path dispatch, above), so geometry is preserved and nothing
  duplicates. **Edge-id grammar (pinned):** `contrib__<personId>__<repoId>` using a
  double-underscore joiner rather than `:` — node ids already contain `-` and could
  contain other separators, so a fixed unambiguous joiner beats a "split on
  first/last `:`" convention that a second producer would drift. (`__` is legal in a
  Firestore doc id; only the wrapping `__x__` reserved pattern is forbidden, which
  `contrib__a__b` does not match.) **Amend `community_projection.dart` + ADR-0003
  Decision 3 together** so the shipped ids ARE the ADR (hyphen node ids,
  double-underscore edge ids) — closing the two-source drift, not papering it.
- **[OPEN-2] Does `_type` belong inside the stamps envelope or as a
  sibling reserved `_type` field?** Leaning: sibling `_type` (envelope stays
  purely `{stamps:...}`; type is identity-adjacent like `id`, not CRDT metadata).
- **[OPEN-3] Dangling-edge render policy** (endpoint not yet arrived): skip vs
  ghost. Leaning: skip (safest for DoS), revisit for liveliness.
- **[OPEN-4] CanvasNode/CanvasEdge as freezed sum vs plain sealed classes** —
  ergonomics only, no correctness weight.

## Temper — round 1 (cross-family design cage-match, PR #19)

Panel: Maxwell + Kelvin (Gemini) + Carnot (GPT) + Tesla (Grok); Wu (Kimi)
dark-seated (CLI not installed). **Verdicts: Kelvin APPROVE; Carnot + Tesla
REQUEST_CHANGES** — held, correctly (no consensus-approve). None of the findings
dissolved the ore; the registry remains load-bearing (confirmed by the
silent-field-loss reframe AND the closed-schema pin, T5 below). Round 1 of ≤3.

**Ledger — every finding classified, all folded (none deferred, none rejected):**

| # | finding | raisers | real? | fold |
|---|---|---|---|---|
| T1 | `nodeSchemaFor => ?? classBoxSchema` is guard-the-window, not remove-the-coupling — a call site past the door reopens silent field loss | Carnot+Tesla | yes | Shape revised: `NodeSchema?`, no default; absence only in reader |
| T2 | edge twin unsealed: `edgeSchemaFor => ?? contributionSchema`; edges have zero legacy docs → **no** default at all | Carnot+Tesla | yes | Shape revised: `EdgeSchema?`, absent/unknown edge type always quarantines |
| T3 | OPEN-1 is a hard gate before Slice 3; blast radius = edge-id tripling + human-geometry destruction | Carnot+Tesla | yes | OPEN-1 elevated + decision matrix above |
| T4 | "already in prod" conflates ClassBox stepping-stone docs with typed ADR docs; Slices 0-2 can't render typed nodes without the producer flip | Carnot | yes | CRUCIBLE.md corrected; done-condition split (below) |
| T5 | claim-1 survives Temper ONLY if schemas stay CLOSED — the real shortcut is open-unit pass-through, not kind-tagging | Tesla | yes | pinned as non-negotiable invariant (below) |
| T6 | join projection underspecified — resolve endpoints at PAINT/emit time against current node view, never drop at absorb on arrival order | Carnot+Tesla | yes | edge-render invariant pinned (below) |
| T7 | quarantine failure-class table missing | Carnot+Tesla | yes | table added (below) |
| T8 | OPEN-2 must be decided before Slice 0 (it IS Slice 0's only behavior change) + type is immutable after create | Carnot+Tesla | yes | decided: sibling `_type`, immutable (below) |
| T9 | DoS claim-5: registry dispatch multiplies throw sites by \|types\| — EVERY registered projector must be total-or-caught, not just the unknown branch | Carnot+Tesla | yes | per-projector quarantine pinned (below) |
| T10 | dual store (`nodes`/`edges` beside `classBoxes`) needs a named single paint-SoT per slice | Tesla | yes | one-paint-source rule (below) |
| T11 | edge delete/tombstone + recreated-edge-conflict semantics only implied | Carnot | yes | noted in edge vertical (below) |

**Folded resolutions:**

- **[T5 — the closed-schema pin, replaces the weak claim-1 rebuttal]** The registry
  is load-bearing because **merge is defined only over declared units**: `_mergeUnits`
  does not carry payload fields for a unit absent from `fieldsOf`, so an unknown unit
  advances its stamp but **drops its fields**. Therefore a render-only `kind`
  discriminator (which would need *open-unit pass-through* to keep Person fields
  through the merge) is not a lighter alternative — it is a **different, weaker CRDT**
  that abandons ADR-0003's closed authority partition. **Non-negotiable invariant:
  schemas stay closed ⇒ the registry is load-bearing for MERGE, not paint.** This is
  the precise falsifier-closure; the earlier "ClassBox has no such fields" rebuttal was
  necessary but not the crux.
- **[T6 — edge-render invariant]** Both `.snapshots()` listeners feed a single
  projection over `(latestAcceptedNodes, latestAcceptedEdges)`. Endpoint resolution
  happens **at emit/paint time against the current node view**, never at absorb —
  independent listeners deliver in any order, so a "missing endpoint" at absorb is a
  lag artifact, not a fact. Render an edge iff both endpoints are present AND neither
  `isDeleted` (subsumes FOLD-2). Edge projection must never depend on listener arrival
  order.
- **[T7 — quarantine failure-class table]** Every remote-input failure gets an explicit
  disposition (Q = quarantine skip+breadcrumb; A = accept):

  | class | disposition |
  |---|---|
  | `_type` absent | A as `ClassBox` |
  | `_type` present + registered | A under its schema |
  | `_type` present + unregistered | **Q** |
  | malformed `_type` (non-string) | **Q** |
  | same-id upgrade: local absent-default `ClassBox` + incoming explicit `_type` | **A as upgrade** (adopt incoming type; geometry unit survives) |
  | same-id flip: local *explicit* type + different incoming type (Person→Repo, …) | **Q** (hostile; `mergeNodes` StateError, per-doc) |
  | missing/empty stamps, blank origin/hlc, unparseable hlc | **Q** (existing door) |
  | malformed geometry (`left:"banana"`) | **Q** (projection dry-run) |
  | reserved `__.*__` field name | **Q** (existing door) |
  | edge: absent/unknown type | **Q** (no default) |
  | edge: endpoint absent or tombstoned | **render-skip** (not quarantine — the doc is valid, just unresolvable this frame) |
  | edge: divergent identity tuple `(id,type,from,to)` | **Q** (mergeEdges StateError) |

- **[T8 — wire discriminator decided]** Sibling reserved `_type` field (NOT inside
  `_envelope`), single-underscore, reserved-name safe. **Type is immutable after
  create** (identity-adjacent, like `id`) — a hostile overwrite of `_type` that flips
  a node's type surfaces as the `mergeNodes` type-mismatch StateError, which the door
  quarantines. Decided **before Slice 0** because Slice 0's behavior-neutral proof and
  the prod-grep assertion both depend on the exact field path.
- **[T9 — per-projector DoS]** The door's contract is "**every** registered projector
  is total-or-caught", not merely `hasNodeType`. Each registered type's projection
  dry-run AND its `mergeNodes`/`mergeEdges` call stay inside the per-doc
  try/quarantine. Adding a type adds a projector = adds throw sites; the RED proof set
  covers unknown-type, registered-type-with-hostile-payload, and same-id-type-flip.
- **[T10 — single paint-SoT during dual store]** Each slice names ONE paint source;
  the other store field is derived or frozen. Slice 4 *deletes* the shadow
  (`classBoxes`), it is not a second migration. No slice paints from two authorities.
- **[T11 — edge lifecycle]** The edge vertical specifies: a tombstone merge rule
  (reuse `EdgeSchema.tombstoneUnit`), a painter exclusion rule (T6), and — because a
  "moved" edge is delete+recreate under a new id — a recreated-edge is a distinct
  document, so no re-point conflict exists by construction (matches `mergeEdges`
  fail-closed on divergent identity).

**Revised done-condition (T4 split):** *registry (Slices 0–2)* = typed ADR docs, when
present, merge and project without field loss; *producer flip (Slice 3)* = the ingest
writes typed docs so they exist to be read. The projector demo ("typed nodes + edges on
the live canvas") is reachable only after **both**, gated behind OPEN-1.

**Temper verdict (round 1):** design-only, held at REQUEST_CHANGES → all findings
folded. **Scope stamp:** this verdict is on the DESIGN; the implementation is UNPROVEN
and still needs a code cage-match per slice (Slice 0 + every merge-core-touching slice
= cage-match by law). A round-2 re-temper on the folded design is warranted before
Blade if the changes are to count as "survived the fire" (round 1's APPROVE was on the
*pre-fold* design; the folds are un-struck).

## Temper — round 2 (re-strike on the folded design, PR #19)

Panel: Maxwell + Carnot (GPT) + Tesla (Grok); Kelvin killed by the review timeout
(0 bytes) → 2-adversary strike, but **both converged**, so the verdict is decisive.
**Verdicts: Carnot + Tesla REQUEST_CHANGES.** Round 2 of ≤3.

**The fatal, NEW, converged finding (T12 — a flaw my own round-1 folds INTRODUCED):**
OPEN-1's leaning ("reuse `gh-person-<id>` ids") **contradicts** T8 ("type immutable;
same-id type flip → quarantine"). The 16 prod docs are ClassBox-typed (absent `_type`)
+ carry human geometry. Slice 3 writes `_type:'Person'` on the *same id* → `mergeNodes`
fails closed on `ClassBox != Person` → the Person write **quarantines forever**. The
security door (hostile flip → Q) and the legitimate migration (stepping-stone → typed)
share one disposition with **no upgrade class**. "Reuse ids + preserve geometry" is
*logically false* under the folded invariants. This is why re-tempering a fold matters:
round 1 couldn't see a flaw the fold hadn't created yet.

**Proposed resolution (T12 — asymmetric upgrade; author's recommendation, un-struck):**
ClassBox-as-absent-default is the ONLY type that may be legitimately upgraded, because
it was never explicitly declared. So distinguish by asymmetry:
- **untyped(ClassBox) → typed** = a legal one-way **upgrade**. The reader recognizes
  "local type is the absent-default ClassBox + incoming carries an explicit `_type`,
  same id" as migration, adopts the new type, and — because `geometry` is a
  unit-partitioned human-owned unit — the human's drag **survives** the upgrade.
- **typed → different-typed** (Person→Repo, or any explicit→explicit flip) stays
  **hostile → quarantine**.
This removes the door/migration coupling instead of guarding it, and preserves demo
geometry. It adds a fourth OPEN-1 matrix row: *same-id upgrade | no dup | geometry
preserved | one-way, untyped→typed only*.

**Scoping realization (the path forward — both adversaries bless it):** the T12
contradiction bites **only Slice 3** (the producer flip). **Slices 0–2 are entirely
reader-side** (registry + typed projection + edge vertical) and are UNAFFECTED — Carnot:
"sound enough for Slice 0 prototype work"; Tesla: "Build Slice 0–2 only after reconciling
`_type` … into one spine" (now done). So the buildable cut is **Slices 0–2 now** (each
cage-match-by-law), with **Slice 3 HARD-GATED** on: (a) the T12 upgrade decision, (b)
OPEN-1 id/edge-id grammar pinned, (c) ADR-0003 amended to match `community_projection`.

**Remaining round-2 findings (folded / classified, none blocking Slices 0–2):**
- Carnot High — type-flip on already-accepted state: entropy accounting (same cluster as
  T12; the asymmetric-upgrade rule + "retain last-good, quarantine only the new version"
  answers it). **Fold into T12.**
- Carnot High — atomic commit model across the two listeners (validate→merge→project
  candidate, then atomically publish; on failure keep prior accepted snapshot). **Fold
  into the edge vertical / Slice 2 spec.**
- Carnot High / Tesla — stale-edge GC after endpoint tombstone: render-skip isn't enough
  once select/delete/export exist. **Named tradeoff** (v1.1; ADR-0003 already defers
  tombstone GC) — store as hidden valid CRDT facts + diagnostics; agent cleanup later.
- Carnot Medium — collapse the folded resolutions back into the main Shape/Build sections
  so there is ONE authoritative design, not pre-fold + errata. **Do before Blade.**
- Carnot Medium — quarantine breadcrumb throttling (bounded telemetry is part of the DoS
  boundary). **Fold** (coalesce by failure-class/time-window).
- Tesla — schema-epoch / registry skew across concurrent writers with different
  registered sets. **Named tradeoff** (prophecy; name before multi-type agents ship, not
  a Slice-0 blocker).

**Temper verdict (round 2):** held at REQUEST_CHANGES on the *full* design (Slice 3
contradiction). **Slices 0–2 are cleared to build** (reader-side, cage-match-per-slice).
Slice 3 needs the T12 decision + OPEN-1 pin, then a round-3 re-temper on that delta. The
folds above are un-struck.
