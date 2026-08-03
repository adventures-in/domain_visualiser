# DESIGN — the typed-merge contract (#2432 / #22, Slices 1–2)

*Fresh Cast. This is the recast the round-3 Temper of
[`../type-aware-read-path/DESIGN.md`](../type-aware-read-path/DESIGN.md)
ordered: "Slices 1+ get a new /crucible (or design+cage-match) pass on the
corrected typed-merge contract before build." Ore + Heat are banked in that
folder's `CRUCIBLE.md` / `RESEARCH.md`; only the **Cast + Temper of the
corrected contract** is un-struck. This doc is the authoritative spine — the
5-part contract is stated as the design, not as errata bolted onto v1.*

**Scope stamp:** DESIGN-only. Slice 0 (ClassBox-only registry) already shipped
live (PR #20, on `main`). This covers **Slice 1 (typed nodes + the upgrade
branch) and Slice 2 (edge vertical)** — both reader-side. Slice 3 (producer
flip) is gated separately on OPEN-1 + ADR-0003 amendment and is NOT in this
temper's build scope.

---

## Why the merge-*time* upgrade rule was the wrong shape (what the fire proved)

The v1 design tried to admit the ClassBox→typed migration *at the merge site*
(a `mergeNodeAdmittingUpgrade` that special-cased a type mismatch). Three
adversary rounds each broke a fold the previous round introduced, all on the
same field:

- **FOLD-1** — `nodeSchemaFor(t) => registry[t] ?? classBoxSchema` collapsed
  absent and unknown-present into one default (silent field loss / DoS leak).
- **T1/T2** — the `??` default was "guard the window"; removed → registry is
  `NodeSchema?`, absence resolved only in the reader.
- **T12** — "reuse ids + preserve geometry" is *logically false* under
  `mergeNodes`' `local.type != remote.type` fail-closed guard
  (`graph_envelope.dart:254`): a `Person` write on a ClassBox id quarantines
  forever. Migration and forgery share one disposition, no upgrade class.
- **T13** — the reader stamped `'ClassBox'` for BOTH absent and explicit
  `_type:'ClassBox'`, so "local is the absent-default" was **not a runtime
  predicate** — the forgery vector reopened one level down.

`FOLD-1 → T1/T2 → T12 → T13`: each fix on the type-transition field spawned the
next flaw on that same field. That escalation IS the
`feedback_complexity_hotspot_is_architecture_smell` tell — the signal to
**revert and fix the contract, not the Nth consumer.** The corrected contract
below removes the coupling (per `concept_remove_coupling_not_guard_window`)
instead of guarding it: the upgrade stops being a merge-time exception and
becomes a **wire law + a write-mask law**, so the merge core never sees a type
mismatch it must forgive.

---

## The corrected contract (the spine — 5 laws)

### Law 1 — Wire law: `ClassBox ⟺ absent _type`

- Writers **MUST NOT** emit an explicit `_type:'ClassBox'`. A doc carrying
  `_type:'ClassBox'` on the wire is **quarantined** (it is an illegal
  serialization — the absent form is the only legal ClassBox encoding).
- Absent `_type` → the reader stamps `type = 'ClassBox'`
  (`_readGraphNodeFromDoc`, already live from Slice 0).
- **Consequence that dissolves T13:** every in-memory node with
  `type == 'ClassBox'` got there via the absence branch (the wire law forbids
  the only other route). So `local.type == 'ClassBox'` is a **sound runtime
  predicate for "this is the upgradable absent-default"** — no `typeWasExplicit`
  provenance bit is needed. The predicate the T12 upgrade rule required is
  *manufactured by construction* at the wire boundary, not reconstructed at
  merge time.
- **Enforcement point:** `_readGraphNodeFromDoc` gains one branch — a
  present-and-equal-to-`'ClassBox'` `_type` throws (→ door quarantine), joining
  the existing present-but-non-String throw (`firestore_backend.dart:210`).

### Law 2 — Write-mask law: typed producers write agent-owned units only

- A typed producer (Slice 3 ingest, and any future typed rewrite) writes
  **only** its agent-owned units + `_type`, and **NEVER** `geometry`. Generalizes
  the existing masked-update discipline (`classBoxToUpdateGraphNode` already
  stamps only the units that changed; `agent_draw_envelope.dart` masks agent
  writes).
- **Consequence:** "preserve the human's drag across an upgrade" becomes a
  **write invariant**, not a merge-time claim. The producer never touches
  geometry, so there is nothing for the merge to protect — the human's geometry
  stamp is simply never contested by the typed write.
- **Slice scope:** the *law* is stated here; its *enforcement in the producer*
  is Slice 3. In Slices 1–2 it is honored by test fixtures (a typed fixture that
  writes geometry is itself an illegal producer and a RED-proof target).

### Law 3 — Single mutator: one absorb/write merge path

- One function `mergeNodeAdmittingUpgrade(local, incoming, registry)` is the
  **sole** merge entry for both absorb (`firestore_backend.dart:164`) and write
  (`:409`). The v1 "3 merge sites each remember the upgrade exception" shape is
  guard-the-window and is removed.
- Its whole body — **the SYMMETRIC absent-default upgrade** (the F1 resolution:
  the absent-default is upgradable in EITHER position, so the mutator is
  commutative):
  1. If `local.type == incoming.type` → `mergeNodes(local, incoming,
     registry.nodeSchemaFor(local.type)!)` — the plain path (schema non-null
     because both types were door-admitted).
  2. Else if **exactly one** side is `'ClassBox'` (the absent-default, Law 1) and
     the other is a registered explicit type → **upgrade to the explicit type**:
     re-key the absent-default side to the explicit type (adopt the explicit
     `_type`, carry that side's existing stamps/payload forward — see F2), THEN
     `mergeNodes` under `registry.nodeSchemaFor(explicitType)!`. Because
     `geometry` is a shared merge unit (Law 4), a human geometry stamp on EITHER
     side survives the re-key untouched. **Position-independent:**
     - `local ClassBox + incoming Person` → adopt Person (the ingest upgrade).
     - `local Person + incoming ClassBox` → adopt Person (a concurrent human
       geometry drag issued while that client still held the node as ClassBox —
       its drag merges into the Person under the geometry unit rather than
       quarantining). **This is the F1 fix — without it, a drag racing an upgrade
       is dropped as a false "hostile downgrade".**
  3. Else (**both** sides explicit AND differ — Person→Repo, Repo→Person, any
     explicit→explicit flip) → **hostile**: let `mergeNodes`' `local.type !=
     remote.type` StateError fire (`graph_envelope.dart:254`) → caught per-doc →
     quarantine. There is no legitimate explicit→explicit transition; type is
     one-way (absent-default → explicit) and terminal.
- **This is the ONLY place the type asymmetry lives.** No call site past this
  mutator can reopen it. **Commutativity (F1):** the operation is symmetric in
  `(local, incoming)` up to which side carried the absent-default, and both
  orders resolve to the same explicit type + the LWW-winning geometry stamp — so
  a dumb transport delivering base and upgrade in any order converges. The forgery
  boundary is unchanged: an explicit→explicit flip is still hostile; only the
  never-declared absent-default is upgradable (Law 1 keeps that predicate sound).

### Law 4 — Shared geometry-unit invariant

- The `geometry` unit **name and fields** (`['left','top','right','bottom']`)
  are **byte-identical** across `classBoxSchema`, `personSchema`, `repoSchema`.
  Asserted by a test (`test/typed_merge/geometry_unit_identical_test.dart`) that
  reads `.mergeUnits['geometry']` off all three and asserts deep equality.
- **Why it is load-bearing:** the re-key in Law 3 step 2 preserves geometry only
  if the incoming schema declares the *same* geometry unit. If Person declared
  `geometry: ['x','y','w','h']`, the re-keyed local's geometry stamp would point
  at a unit whose fields the new schema does not carry — geometry would advance
  its stamp while dropping its fields (`_mergeUnits` drops fields of unknown
  units — `graph_envelope.dart:208`), destroying the drag. The invariant makes
  the upgrade geometry-safe *structurally*.
- On upgrade, `label → profile` fields are incoming-wins by ordinary LWW (the
  agent write carries a later HLC); geometry is untouched (human-owned, never
  written by the producer per Law 2).

### Law 5 — Named integrity tradeoff (owner: Nick to accept)

- Under Laws 1–4, an **unauthenticated peer can upgrade ANY ClassBox id** —
  including a human-drawn UML box — to Person/Repo, because the id prefix is
  advisory and the envelope `_type` is authoritative. Hostility begins only at
  explicit→explicit flips.
- This is a **capability, not a DoS leak**: it is per-doc (batch survives), it
  cannot crash the canvas, and it cannot destroy geometry (Law 4). Its worst
  case is a nuisance re-typing of one node, itself visible and correctable.
- **If unacceptable**, the gate is a one-line predicate in Law 3 step 2: admit
  the upgrade only if `incoming.id` matches an id-grammar allowlist
  (`gh-person-*` / `gh-repo-*`) OR the writer principal is trusted. Stated so
  Nick can accept or gate it explicitly — not hidden.

---

## Code deltas (grounded in the real Slice-0 core)

| site | file:line (current) | delta |
|---|---|---|
| reader | `firestore_backend.dart:206–214` | add branch: `_type` present AND `== 'ClassBox'` → throw `FormatException` (Law 1). Absent → ClassBox unchanged. |
| registry | `schema_registry.dart:44` | register `personSchema`, `repoSchema` in `defaultRegistry` node map; add `contributionSchema` to edge map (Slice 2). |
| new schemas | `lib/graph/community_schemas.dart` (new) | `personSchema` (units: `profile`[login,name,avatarUrl,htmlUrl,kind] + `geometry` + `curation`), `repoSchema` (`meta`[...] + `geometry` + `curation`), `contributionSchema` edge (`weight`[commits]). Geometry unit byte-identical to ClassBox (Law 4). |
| single mutator | replaces `mergeNodes(...)` at `:164` and `:409` | new `mergeNodeAdmittingUpgrade(local, incoming, _registry)` (Law 3). |
| edge absorb | `firestore_backend.dart:121` early-return | Slice 2: a **sibling** `.snapshots()` listener on an `edges` collection, NOT reusing the `!= classBoxes` gate. Its own `_tryReadValidEdge` door. |
| projection | `_emitProjection:350` | Slice 1: dispatch projection by `node.type` → `PersonNode`/`RepoNode`/`ClassBoxNode` (still box-rendered in Slice 1). Slice 2: also emit `IList<CanvasEdge>`. |
| atomic publish | `_emitProjection` + edge emit | Slice 2: publish `(nodes, edges)` from immutable accepted maps in one action; retain-last-good per doc on failure. Endpoint resolution at **paint time** over the current joined view (skip iff endpoint absent OR `isDeleted`), never absorb-time on arrival order. |

---

## Degenerate-state table (pre-Fold — the adversary CONFIRMS, not discovers)

Every remote-input state and its disposition (Q = quarantine skip+breadcrumb;
A = accept; U = accept-as-upgrade; RS = render-skip):

| # | state | disposition | mechanism |
|---|---|---|---|
| S1 | `_type` absent | A as ClassBox | reader default (live) |
| S2 | `_type` present + registered (Person/Repo) | A under its schema | reader + registry |
| S3 | `_type` present + unregistered (`'Comment'`) | **Q** | door `hasNodeType` (live) |
| S4 | `_type` present + non-String | **Q** | reader throw (live, `:210`) |
| S5 | **`_type` present + `== 'ClassBox'`** | **Q** | **NEW (Law 1)** — illegal serialization |
| S6 | same-id: local ClassBox(absent-default) + incoming explicit registered | **U** | mutator step 2; geometry survives (Law 4) |
| S7 | same-id: local explicit + incoming different explicit (Person→Repo) | **Q** | mutator step 3 → `mergeNodes` StateError `:254` |
| S8 | same-id: local explicit + incoming ClassBox absent-default (a concurrent human drag) | **U** | mutator step 2 (symmetric) — adopt local's explicit type, merge incoming geometry; **NOT** a downgrade. This is the F1 fix. |
| S9 | upgrade candidate with malformed payload (`left:"banana"`) | **Q** | door projection dry-run before mutator |
| S10 | upgrade candidate missing a compatible geometry unit | **Q** (or A with fresh geometry?) | **adversary target** — see Fold F3 |
| S11 | typed doc, no stamps / blank origin-hlc / unparseable hlc | **Q** | existing door checks |
| S12 | reserved `__.*__` field name | **Q** | existing door (face d) |
| S13 | edge: absent/unknown type | **Q** | edge door, no default |
| S14 | edge: endpoint absent OR tombstoned | **RS** | paint-time resolution (not Q — doc is valid) |
| S15 | edge: divergent identity tuple `(id,type,from,to)` | **Q** | `mergeEdges` StateError |
| S16 | concurrent: two peers upgrade same ClassBox id to *different* types | first-writer-wins by HLC; the later different-explicit → **Q** (S7) once one lands | **adversary target** — convergence under Law 3, see Fold F1 |

---

## Fold (author self-pass — degenerate states I flag BEFORE the strike)

- **[F1 — RESOLVED in-design via the symmetric upgrade; residual handed to the
  panel]** The naive rule (upgrade only when `local == ClassBox`) is
  **non-commutative**: a human geometry drag issued while a client still holds
  the node as ClassBox arrives as `incoming.type == ClassBox` against a local
  `Person` (if the upgrade transaction landed first) → a naive step-3 quarantines
  it as a "hostile downgrade" → **the drag is silently dropped.** Resolution
  (folded into Law 3): the absent-default is upgradable in **either** position —
  if exactly one side is ClassBox, adopt the *other's* explicit type and merge,
  so both orderings converge and the drag's geometry stamp survives by LWW.
  **Residual for the adversary (claim #1):** does the symmetric rule stay
  commutative AND non-forgeable under a THREE-way race (base + upgrade-to-Person +
  a hostile upgrade-to-Repo, all same id)? My reasoning: the first explicit type
  to win the `_type` slot makes the node explicit; any later *different* explicit
  is then step-3 hostile → Q; a later ClassBox absent-default is step-2 absorbed
  under the won type. Convergence should hold because "which explicit won" is
  itself an LWW over the `_type`-bearing stamp — **but I have not proven the
  `_type` slot orders consistently with the unit stamps.** Strike here.
- **[F2 — the mutator's re-key must carry stamps, not reset them]** Step 2
  re-keys local ClassBox → Person. If it rebuilds the node with fresh stamps,
  the human's geometry stamp is lost and a concurrent geometry edit could tear.
  The re-key must be a pure type-field change: same `id`, new `type`, **same
  `payload` + same `stamps`**, then `mergeNodes` under the Person schema. Assert
  in a RED proof: geometry stamp HLC is byte-identical before/after upgrade.
- **[F3 — S10: upgrade to a schema whose geometry unit the local lacks]** If a
  future typed schema (not Person/Repo) omitted geometry, the re-key would strip
  it. Law 4 forbids this for Person/Repo, but the *mutator* should not assume —
  it should assert `nodeSchemaFor(incoming.type)` declares a geometry unit
  compatible with local's, else **Q** (not silent strip). Belt-and-suspenders on
  the Law-4 test.
- **[F4 — projection dispatch is a new throw fan-out (T9 lives on)]** Every
  registered projector (`PersonNode`/`RepoNode`) adds a throw source to
  `_emitProjection`. Each MUST stay inside the existing per-node
  try/quarantine (`:358`). RED proof: a registered-but-hostile-payload Person
  doc quarantines, batch survives.
- **[F5 — edge painter never couples validity to node-arrival order]** (T6,
  carried) resolve endpoints at paint time over the current joined view; render
  iff both endpoints present AND neither `isDeleted`. RED proof: a
  `contribution` edge referencing a not-yet-arrived Person renders nothing, then
  appears when the Person lands — no throw, no quarantine.
- **[F6 — the upgrade exposes a UNIT-NAME mapping the merge silently drops]** A
  ClassBox carries a `label` unit; `personSchema` has no `label` unit (it has
  `profile`). On upgrade, `_mergeUnits` drops fields of units absent from the
  adopted schema (`graph_envelope.dart:208`) — so the human's typed **box label
  is silently lost** on ClassBox→Person unless it is preserved. Two candidate
  resolutions, adversary to pick: (a) `personSchema`/`repoSchema` KEEP a `label`
  unit (byte-identical to ClassBox's) so a human-typed label survives independent
  of the agent `profile.name`; OR (b) the upgrade maps `label → curation.displayLabel`
  (the human-owned curation unit) so the human's name wins over the agent's. I
  lean (a): it is the same structural move as Law 4 (shared unit, no mapping
  logic), and it keeps "human typed a name on a box" orthogonal to "agent knows
  the GitHub login". **Flagged; the geometry invariant (Law 4) should generalize
  to a shared HUMAN-OWNED unit set `{geometry, label, curation}`, not geometry
  alone.**

---

## Claims to falsify (hand these to the four-family panel)

1. **[F1] The symmetric mutator stays commutative AND non-forgeable under a
   THREE-way race** — base(ClassBox) + upgrade(Person) + hostile-upgrade(Repo),
   all same id, delivered in every order. Show either a non-convergent end state,
   a dropped human geometry/label stamp, or a Repo winning over a Person that a
   real producer wrote. *The pairwise case is resolved in-design (symmetric
   rule); the `_type`-slot-vs-unit-stamp ordering under 3-way concurrency is the
   unproven residual — strike here first.*
2. **Law 1 makes `local.type=='ClassBox'` a sound upgrade predicate** — find any
   route by which an in-memory ClassBox node did NOT come from an absent `_type`
   (i.e. an explicit `_type:'ClassBox'` that slipped past the reader throw).
3. **Law 4 makes the upgrade geometry-safe structurally** — find a schema pair
   where a byte-identical geometry unit still tears geometry on upgrade.
4. **The DoS boundary survives |types| projectors** — craft a registered-type
   doc (Person) with a hostile payload that throws OUTSIDE the per-doc guard.
5. **Edge sibling-listener needs no cross-collection ordering** — craft an edge
   whose endpoint never arrives, or arrives then tombstones mid-frame, and show
   the painter throws or leaks a ghost line.
6. **Slices 1–2 are truly Slice-3-independent** — find a reader-side behavior
   that is unobservable/untestable without flipping the producer.

---

## Build order (unchanged from the tempered v1 skeleton, re-scoped)

- **Slice 1 — typed nodes + upgrade branch (cage-match by law).** Register
  Person/Repo; new schemas (Law 4 geometry); single mutator (Law 3); reader Law-1
  throw. RED proofs: S5, S6 (+F2 stamp-identity), S7, S9, F4. **The upgrade
  branch is reachable HERE** (Tesla's round-3 correction — registration alone
  changes dispatch), so F1 commutativity is a Slice-1 gate, not deferred.
- **Slice 2 — edge vertical (cage-match by law).** Sibling listener + own door +
  `contributionSchema` + `CanvasEdge` store + paint-time endpoint resolution.
  RED proofs: S13, S14/F5, S15, atomic-publish retain-last-good.
- **Slice 3 — producer flip. HARD-GATED, NOT in this temper.** Gated on OPEN-1
  (id/edge-id grammar) + ADR-0003 amendment + write-mask enforcement in the real
  producer. Verified by a live prod audit (check `.error` before trusting
  `.documents|length` — the broken-instrument lesson from the `_type` audit).

## Done-condition for THIS temper

2 consecutive rounds converge with no fatal finding, OR the ≤3-round bound is hit
and the residual is a named tradeoff. F1 (commutativity) is the crux — if it
survives with a clean resolution folded in, the contract is blade-ready for
Slice 1.

---

## Temper — round 1 (four-family design cage-match, PR #21)

Panel: Maxwell (author) + Kelvin (Gemini) + Tesla (Grok) + Wu (Kimi). Carnot
(GPT-5.5 xhigh) hung mid-strike (stalled re-reading generated `freezed.dart`;
retired — its absence does not change a unanimous verdict). **Verdicts: Kelvin,
Tesla, Wu ALL REQUEST_CHANGES, decisively converged.** Round 1 of ≤3.

**The converged fatal — F-A (the crux; all three families, independently):**
`GraphNode.type` is **immutable identity with NO stamp** (`graph_envelope.dart:247-259`),
so the type transition is resolved by **arrival/processing order, never LWW**.
- Multi-explicit race (base ClassBox + upgrade→Person + upgrade→Repo, same id):
  `ClassBox→Person→Repo` ends **Person**; reversed ends **Repo** — permanent
  divergence between replicas (Kelvin, Tesla; Tesla simulated it 50/50).
- Worse on the write path (Wu): `_writeMerged` **catches** the explicit→explicit
  `StateError` (`firestore_backend.dart:445-450`) and writes the local merge back,
  so a local Person writer **clobbers** a remote Repo.
- The design's "first-writer-wins by HLC" residual (claim #1) **has no mechanism
  in the code** — there is no `_type` stamp to order. My symmetric-upgrade fix
  **relocated the coupling into the re-key, did not remove it.** This is the same
  type-field hotspot as `FOLD-1 → T1/T2 → T12 → T13`, one level down — the 5th
  consecutive failure on the same field.

**Converged supporting findings:**
- **F-B [FATAL, Tesla + Wu] — the durable write never serializes `_type`.**
  `_toFirestoreDoc` (`firestore_backend.dart:459-475`) spreads `payload` +
  `_envelope` only, never `typeKey`; and `classBoxToGraphNodePartial` emits
  `type:'ClassBox'` on a human drag. So even a correct in-memory upgrade is not
  durable — cold readers re-materialize ClassBox, agent fields orphan.
- **F-C [FATAL/HIGH, all three] — the shared human-owned unit set is
  insufficient.** `classBoxSchema` + `withContainerUnits` carry `label`, four UML
  list units, `parent`, `containerType`, `zIndex` (`class_box_schema.dart:28-38`,
  `container_schema.dart:49`); the designed `personSchema`/`repoSchema` keep only
  `geometry`+`curation`+`profile`/`meta`. On upgrade these human units leave the
  contract (orphaned, not projected). Also `curation` is NOT on ClassBox today —
  my Law-4 "byte-identical across all three" is internally inconsistent.
  Correction (Tesla): `_mergeUnits:208` does not *delete* unknown-unit fields;
  they linger as orphans — the loss is contract/projection, not a line-208 strip.
- **F-D [MED, Tesla] — the door projectability dry-run is ClassBox-hardcoded**
  (`_tryReadValidNode` always `graphNodeToClassBox`, `:311`). A registered-Person
  doc with a Person-illegal payload is not validated at the trust boundary; the
  design's S9 "door dry-run before mutator" is false for typed schemas until the
  dry-run dispatches by type.
- **Enforce Law 1 at BOTH doors (Wu):** the reader `FormatException` on explicit
  `_type:'ClassBox'` must land on the absorb reader AND the tx-read path, or T13
  reopens.
- Not falsified: claim #5 (edge paint-time resolution) and claim #6 (edge/slice
  independence) held; claim #2's predicate is operationally OK once the Law-1
  throw lands (prose "provenance" overstated, not fatal).

**Verdict (round 1): REQUEST_CHANGES, unanimous. The merge-time-upgrade shape is
confirmed dead (5th strike on the type field).** Per
`concept_remove_coupling_not_guard_window` + `feedback_complexity_hotspot_is_
architecture_smell`, the resolution is NOT a round-2 fold on another merge-time
patch — it is to change what `type` IS. The root coupling: **`type` is treated
as immutable identity while the upgrade feature requires it to change.** Two
clean ways to remove it — a stamped-LWW type field, or an id-derived
deterministic type — are a design fork that changes the identity/security model
and reverses the v1 "id-prefix advisory" rejected-alternative, so it is escalated
to Nick before round 2.

---

# RECAST v2 — the collapsed contract (post-live-audit)

*This section SUPERSEDES the 5-law contract above. That contract, and all five
Temper rounds against it, existed to solve one problem: migrate the ClassBox
stepping-stone community docs to typed nodes **while preserving human geometry**.
A live-prod audit (below) proves that problem does not exist. The upgrade
machinery is deleted, not fixed.*

## The falsifying evidence (live prod, codraw.ink `domain-objects`, audited)

27 real docs. The 16 community docs (`gh-person-*` ×10, `gh-repo-*` ×6) each carry
exactly `{_envelope, geometry(left/top/right/bottom), name, userId}` — **no
`_type`, no typed fields** (no login/avatarUrl/commits). Decisive: **every stamp
on every `gh-*` doc has `origin == 'agent-github'`** (the producer) for BOTH the
`geometry` and `label` units. Verified programmatically: `16/16 gh-* docs, every
stamp origin == agent-github → True`.

**Consequence:** no human has ever dragged or renamed a community node. There is
**zero human-owned data** on the docs the upgrade was built to protect. The v1
OPEN-1 matrix rejected "tombstone + recreate" because it "DESTROYS human
geometry" — that rejection's premise is **false for the real data**. The cheap
option was rejected on an unverified premise.

## The contract

1. **`type` is a `NodeType` enum, and it is IMMUTABLE identity — unchanged from
   the shipped core.** `mergeNodes`' `(id, type)` identity guard
   (`graph_envelope.dart:254`) stays exactly as-is. There is **no upgrade, no
   type stamp, no LWW-on-type, no merge-time re-key, no id-prefix parsing.** The
   entire class of flaws (FOLD-1 → F-A) is deleted with the machinery that caused
   it.
2. **The wire carries a `_type` string; the reader parses it to `NodeType?` at
   the door.** `absent → NodeType.classBox` (backward compat, live from Slice 0);
   `present + parseable + registered → that variant`; `present + unparseable /
   unregistered / explicit 'ClassBox' → quarantine`. The `String → NodeType?`
   parse **is** the trust-boundary admission check — a typo or hostile string
   yields null → quarantine, never a wrong-schema merge. Downstream dispatch
   (projection, door dry-run) is an **exhaustive `switch (NodeType)`** — the
   compiler forbids a missing case (kills finding F-D structurally).
3. **A node's type is decided ONCE, at create time, by its writer, and never
   changes.** The producer writes `_type:'Person'`/`'Repo'`; a human-drawn box
   writes absent (`ClassBox`). Same id never legitimately changes type.
4. **Migration = tombstone-and-recreate, not merge.** Slice 3's producer
   tombstones (or the `removed` docChange strips) the 16 absent-`_type` docs and
   writes fresh typed docs. A client processes `removed` (strips the ClassBox
   from `_replica`, `firestore_backend.dart:125`) **then** `added` (a clean
   typed insert — `existing == null` branch at `:158`, no merge). **The same-id
   type-flip merge is never reached**, so the immutable-identity guard never
   fires. Safe *because* there is no human data to lose.
5. **Write-mask law survives as forward hygiene (not migration machinery).** A
   typed producer writes only agent-owned units, never `geometry`. Irrelevant to
   the 16 docs today (agent owns everything on them); it matters the day a human
   drags a *typed* node, so keep it — but it is not load-bearing for this
   migration.

## What each prior FATAL becomes under the recast

- **F-A (multi-explicit race diverges):** DELETED. Two different explicit types on
  one id cannot arise — type is create-time and immutable; a producer mints one
  type per id deterministically. A hostile second type on the same id hits the
  existing `mergeNodes` divergent-identity quarantine (a per-doc skip, the shipped
  DoS behaviour), which is *correct* — there is no legitimate transition to
  protect.
- **F-B (write door doesn't serialize `_type`):** shrinks to a real but bounded
  Slice-3 delta — `_toFirestoreDoc` must emit `typeKey` for non-ClassBox writers.
  No in-memory upgrade to keep durable; the producer just writes the field.
- **F-C (shared human-owned unit set insufficient):** DELETED as a *loss* risk —
  nothing is upgraded, so no unit is dropped mid-transition. The gh-* docs have no
  UML/container units at all. (Person/Repo schemas still declare their own units;
  no cross-schema geometry-identity invariant is needed because no re-key occurs.)
- **F-D (door dry-run ClassBox-hardcoded):** fixed structurally by the exhaustive
  `switch (NodeType)` in the projectability dry-run + emit.

## Code deltas (smaller than v1)

| site | delta |
|---|---|
| `graph_envelope.dart` | introduce `enum NodeType { classBox, person, repo }` (+ `NodeType? parseNodeType(String)`); `GraphNode.type` / `NodeSchema.type` become `NodeType`. Identity guard unchanged. |
| `schema_registry.dart` | key by `NodeType`; register person/repo. |
| `firestore_backend.dart:206` | reader parses `_type` → `NodeType?`; absent→classBox; explicit `'ClassBox'` or unparseable/unregistered → throw → door quarantine. |
| `firestore_backend.dart` projection | `_emitProjection` dispatches `switch (node.type)` → `PersonNode`/`RepoNode`/`ClassBoxNode`; door dry-run dispatches the same. |
| new `community_schemas.dart` | `personSchema`/`repoSchema`/`contributionSchema` (own units; no forced geometry-identity). |
| **NO** new mutator | `mergeNodes` untouched; the v1 `mergeNodeAdmittingUpgrade` is not built. |
| Slice 3 `_toFirestoreDoc` | emit `typeKey` for typed writers; ingest tombstones-then-writes typed. |

## Degenerate states (recast)

| # | state | disposition |
|---|---|---|
| R1 | `_type` absent | accept ClassBox (live) |
| R2 | `_type` present, parses to registered variant | accept under its schema |
| R3 | `_type` present, unparseable/unregistered/explicit 'ClassBox' | **Q** (door) |
| R4 | same-id, local ClassBox + incoming Person (NO removal between) | **Q** (mergeNodes divergent-identity — shipped) — and this only happens if a producer writes typed WITHOUT tombstoning first, which is a producer bug the Slice-3 spec forbids |
| R5 | tombstone-then-recreate typed (the migration path) | clean: `removed` strips, `added` inserts — no merge |
| R6 | human drags a `gh-*` node BEFORE Slice 3 | its geometry stamp becomes human-origin; then R4 would lose it → **the one caveat**: run re-ingest before inviting typed-node drags (see Fold) |
| R7 | edge: absent/unknown type | **Q** (Slice 2) |

## Fold (author self-pass on the recast)

- **[RF-1 — the R6 window is the only residual, and it is operationally
  closeable]** If a human drags a `gh-*` node between now and Slice-3 re-ingest,
  that drag's geometry gets a human origin, and tombstone-recreate would drop it.
  Mitigations, cheapest first: (a) run the Slice-3 re-ingest as a single
  operation before any public invitation to edit community nodes (the nodes are
  not individually meaningful to drag yet — they render as plain boxes today);
  (b) the re-ingest can *read current geometry and carry it forward* on the
  recreate (producer reads the old doc's geometry unit, writes it into the new
  typed doc) — turning tombstone-recreate into geometry-preserving-recreate at
  the *producer*, with no merge-core change. (b) makes R6 a non-issue entirely
  and is cheap. **Recommend (b).**
- **[RF-2 — R4 must be impossible-by-producer-discipline, not by merge logic]**
  The recast's safety depends on the producer ALWAYS tombstoning before writing a
  typed doc at a formerly-ClassBox id. If a producer writes `_type:'Person'` to a
  live ClassBox id without removal, clients quarantine it (shipped divergent-id
  guard) and the node vanishes for them. This is a Slice-3 producer contract +
  RED proof (write typed-without-tombstone → assert quarantine breadcrumb), not a
  merge-core concern. Name it so Slice 3 can't forget it.
- **[RF-3 — enum migration is a workspace-wide type change]** `GraphNode.type`
  String→enum touches every construction/read site (projection, tests, the
  agent-draw envelope, community_projection). Compile-driven — the analyzer finds
  them all — but it is the real bulk of Slice 1. Not a risk, a scope note.
- **[RF-4 — is ClassBox-as-absent still worth keeping, or emit `_type` for all?]**
  Keeping absent⟺ClassBox preserves Slice-0's zero-migration for human boxes
  (they never carry `_type`). Alternative (emit `_type:'ClassBox'` explicitly)
  would break every existing human doc's read. Keep absent⟺ClassBox. (This is the
  ONE piece of the v1 "wire law" that survives — as a serialization default, never
  as a dispatch/upgrade predicate.)

## Claims to falsify (recast — hand to the panel)

1. **The upgrade genuinely never needs to exist.** Find a REACHABLE scenario in
   the community-graph demo (Slices 1–3) where a node must change type on the same
   id *and* carries data that tombstone-recreate would lose — given the audited
   fact that all 16 gh-* docs are 100% agent-origin. If R6 is the only one, is
   RF-1(b) a complete closure?
2. **Tombstone-recreate is race-clean.** Craft an ordering (removed/added
   interleaved with a concurrent write from another origin) where the client ends
   with the ClassBox and the Person both live, or neither, or a merged mongrel.
3. **The `String→NodeType?` parse is a complete trust boundary.** Find a wire
   `_type` value that reaches a schema/projection without passing the parse-or-
   quarantine gate.
4. **The exhaustive `switch (NodeType)` actually closes F-D.** Find a projection/
   door path that dispatches on type WITHOUT the compiler forcing all cases.
5. **Edge vertical (Slice 2) is unaffected** by the recast (it never had an
   upgrade problem — edges have no legacy docs).
6. **RF-2's producer discipline is sufficient** — is there a NON-producer path
   (hostile peer, console edit) that writes a typed doc to a live ClassBox id and
   causes worse than a per-doc quarantine?

## Done-condition (recast Temper)

2 consecutive rounds converge with no fatal, or ≤3 hit with a named residual.
Expectation: this is a fraction of the v1 surface (no mutator, core untouched), so
it should converge fast — the test is whether deleting the machinery reopened
anything the machinery was hiding.
