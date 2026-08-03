# CRUCIBLE — the type-aware read path (#2432 / #22)

*Ore pre-selected by Nick; consent gate crossed by explicit target. Forged 2026-08-02.*

## The pick

Generalize `FirestoreBackend`'s read/merge/project path from a single hardwired
`classBoxSchema` to a **type → NodeSchema/EdgeSchema registry**, and add the
missing **edge sync vertical**, so the community graph stops being generic UML
boxes and renders as **distinct typed Person/Repo nodes joined by contribution
edges** on the live canvas.

> **Correction (Temper, Carnot's finding #4):** the 16 docs in production
> Firestore (PR #16) are the **ClassBox stepping stone** (geometry + name), NOT
> typed ADR-0003 Person/Repo docs. A read registry alone (Slices 0–2) cannot
> recover `profile`/`meta`/`commits` fields that were **never written**. The typed
> result therefore requires BOTH the read registry AND the producer flip (Slice 3
> re-writes the ingest to emit typed docs). "Already in prod" describes the
> stepping-stone boxes, not the typed nodes — the earlier framing conflated the
> two. Split cleanly: *registry* = read typed docs correctly; *producer flip* =
> create them.

## Why this thrills me — AND what it changes

The heat: this is the *single cut-vertex of the whole project's dependency
graph*. Everything alive downstream — edge-click labels (#2438), multi-select
delete of edges (#2336), fractal subgraph expand (#2439) — is unreachable until
edges and typed nodes actually render. One vertical unblocks four tasks and the
demo thesis at once.

What it changes, concretely: the agent-as-peer proof stops being a thing you
read in a Firestore console and becomes a thing you point a projector at in a
room. PR #16 already put `nickmeinhold @ 541 commits` into prod as the largest
node; this increment draws the *edges* that make him visibly the cut-vertex —
`subtract-the-cut-vertex` rendered on real data, live, while a human drags boxes
beside the agent's writes. That's the demo the whole codraw thesis has been
walking toward since the July CRDT-peer proof.

The *oh, of course*: the engine already has `GraphEdge`/`EdgeSchema`/`mergeEdges`
(PR #9) — fully built, fully tested, **completely unwired**. The most alive move
isn't inventing machinery; it's connecting a vertical that's been sitting there
finished on one end and blind on the other.

## The falsifier (what would prove this ore is slag)

**If rendering distinct typed nodes turns out NOT to require a registry at all** —
i.e. if carrying a `kind` discriminator on the existing `ClassBox` projection is
enough to draw Person-vs-Repo differently, and edges can ride the existing node
collection — then the "type→schema registry" framing is over-engineering and the
real ore is a 20-line painter change plus an edge collection, not a merge-core
generalization. **The registry only earns its place if per-type merge-unit
partitioning (ADR-0003: agent-owned `profile`/`meta` vs human-owned `geometry`)
is load-bearing on the READ side, not just the write side.**

This is the exact assumption Fold and Temper must strike first: *does the read
path actually need to know the type to merge correctly, or only to render?*
Because `mergeNodes` fails **closed** on `schema.type != node.type`, and every
incoming Person/Repo doc currently hits `classBoxSchema`, the answer leans
"registry is real" — but that must be proven against the merge semantics, not
asserted from the ADR's elegance.

## Aliveness × impact

- **Aliveness: 3** — evidence: it's the named crux in the consolidation
  handoff, it unwires a subsystem (`GraphEdge`) that shipped finished 7 PRs ago
  and has never rendered a pixel, and it's the one thing between "prod fact" and
  "projector demo".
- **Impact: 3** — evidence: single cut-vertex unblocking #2438 + #2336 + #2439 +
  the demo; removes the "the graph is invisible" blocker on a live thesis.
- **Product: 9.** Peak of the melt.
