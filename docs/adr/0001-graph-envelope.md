# ADR-0001 — A generic node/edge envelope for the collaborative graph engine

- **Status:** Proposed
- **Date:** 2026-05-27
- **Deciders:** Nick (+ the AMR / Imagineering graph-builders this is meant to serve)
- **Context source:** `~/.claude/projects/-Users-nick-git/memory/project_graph_engine*.md`

## The problem, stated precisely

Several people in one Melbourne community are each building a different layer
of the same thing — a collaborative knowledge-graph engine — without having
named the shared substrate:

| Builder | Project | Layer | Speaks |
|---|---|---|---|
| Nick | **domain_visualiser** | collaborative canvas | `{id, left, top, right, bottom, name, …methods}` |
| Nick | **Engram** | KG learning app (shipped CRDT) | `concept / relationship / quizItem` welded to FSRS |
| Andy Gelme | **Aiko** | transport / pipeline graphs over MQTT | `"(PE_0 (PE_1 (PE_3 PE_5)))"` |
| Angie Simmons | **SignalKG** | causal / Bayesian layer | sensor-fusion KG |
| Robin Langer | **INSTINCT** | extraction | arXiv → L0/L1/L2 concepts |

**These do not speak the same language.** Without a universal ontology *or* a
schema-agnostic envelope, a "shared engine" only ever talks to itself. So the
first move is not "extract Engram's CRDT mechanism" — it is:

> **Define the generic node/edge envelope before any engine code.**

## The three poles we chose between

1. **Universal generic envelope** — `{id, type, payload, meta}`, schema-agnostic,
   each app registers its own deserializer. Maximally decoupled; pushes all
   typing to the edge.
2. **Translation at the transport boundary** — every pair of apps writes an
   adapter. Flexible, but O(n²) adapters and runtime-fragile.
3. **Hybrid** — generic envelope *in transit*, typed *at the app edge*. The wire
   format is universal; an app deserializes its own `type` into its own model.

**Decision: pole 3 (hybrid).** Pole 2's adapter matrix doesn't scale across five
projects; pole 1 alone leaves no path back to type safety inside each app.
Hybrid gives one wire format plus typed edges — the only option that lets the
engine carry *all five* vocabularies without understanding any of them.

The envelope is `GraphNode { id, type, payload: Map, stamps: Map<unit,FieldStamp> }`
(`lib/graph/graph_envelope.dart`) with a JSON Schema contract
(`graph-node.schema.json`).

## The crux: merge units, not fields

The CRDT metadata is the hard part, and "per-field LWW" is the wrong default —
it is **simultaneously too coarse and too fine**:

- **Too fine** for geometry. domain_visualiser's `left/top/right/bottom` must
  move as *one* unit. If two users drag the same box and each field LWWs
  independently, replicas can take Alice's `left` and Bob's `right` — a **torn
  box** that exists on no one's screen.
- **Too coarse** for the box as a whole (Engram's row-level choice). domvis is
  *multi-user real-time*, where "Alice drags box X while Bob renames X" is the
  **main** case, not an edge case — and that's two independent writes that must
  both survive. Row-level LWW would silently drop one.

So the unit of last-writer-wins is an **app-declared grouping of fields** — a
*merge unit*. domain_visualiser's `ClassBox` declares: `geometry` =
{left,top,right,bottom}, `label` = {name}, and one unit per method/variable
list. The engine honours the declaration; it never guesses the grain.

> This is the precise, load-bearing way to read the forward plan's instruction
> to "copy Engram's CRDT *mechanism*, not its `GraphChangeset` row structure."
> Engram is row-level LWW (`lib/src/crdt/graph_changeset.dart`, verified
> 2026-05-27); we lift its HLC + tombstone *lifecycle* and re-grain it per unit.

**Tombstones are just another merge unit** (`__tomb__` stamping a `__deleted__`
flag), so delete-vs-edit and resurrection resolve through the same LWW loop with
no special-casing. Elegant, and it means `mergeNodes` is a single uniform pass.

## Decisions that need a second pair of eyes (open forks)

1. **Origin: derived or stored?** A `package:crdt` HLC already embeds its
   nodeId, so `origin` is redundant. We store it explicitly anyway, so
   echo-suppression needs no HLC parser and non-`crdt` producers stay valid.
   *Recommended; flagged because it is a denormalization.*
2. **List fields are LWW for v1, OR-Set later.** The method/variable lists are
   genuinely sets and want OR-Set (concurrent adds both survive). v1 treats each
   list as one LWW unit (last writer replaces the whole list) because in a live
   drawing demo concurrent edits to *the same box's method list* are rare. **OR-Set
   is the known first upgrade** — named here, not deferred silently (cf.
   Engram's row→per-field upgrade path).
3. **HLC as `String` in the envelope.** Stamps store the canonical sortable HLC
   string, not a `package:crdt` `Hlc` object, so the envelope type is
   dependency-free. Clock *generation* (increment/merge) stays in the app layer.

## Sequencing (locked — rule of three)

This envelope is implemented **inside domain_visualiser** as the *2nd*
independent CRDT instance (Engram is the 1st). We do **not** refactor mature,
shipping Engram to feed this. The shared package is extracted only when a **3rd**
consumer (INSTINCT / Aiko) wants it — and Engram migrates onto the proven core
**last**, because as the most mature it carries the least risk from waiting.

## Consequences

- domain_visualiser gets conflict-free multi-user editing without an
  authority-rule / echo-suppression design (CRDT makes re-apply idempotent).
- The JSON Schema is the **vocabulary-alignment artifact** to put in front of
  AMR / Imagineering: agree the envelope before anyone writes engine code.
- **Agent-as-peer falls out for free:** a CRDT writer is just an origin + HLC.
  Nothing says it's human. A Claude instance publishing stamped changesets is a
  conflict-free peer at the table. (Open: agent writes are conflict-*free*, not
  automatically *trusted* — auth boundary is a separate ADR.)
