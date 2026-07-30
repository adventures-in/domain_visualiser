# ADR-0003 — The GitHub community-graph schema (v1)

- **Status:** Proposed (grounded in queried data — 2026-07-31)
- **Builds on:** ADR-0001 (the generic envelope), ADR-0002 (agent-as-peer + the GitHub community-map test case)
- **Supersedes:** the concrete GitHub→GraphNode mapping table in ADR-0002 §"GitHub → GraphNode mapping" — two of its `id` choices were mutable keys; see Decision 3.
- **Concepts:** `concept_schema_impedance_mismatch`, `concept_merge_unit_grain`, `identity-as-mutable-key`, `sot_symmetric_deletion`

## What changed since ADR-0002

Three things moved:

1. **Edges are now first-class.** ADR-0002 Open Question 1 ("edges are not yet
   first-class") is **resolved** — `GraphEdge` shipped in PR #9. The community
   map's `Person —contributes-to→ Repo` relationships are directly expressible.
2. **We queried the real data instead of assuming it.** ADR-0002's mapping table
   was written from memory. This ADR is written against the actual GitHub API
   payloads for the `adventures-in` org (see "Verified ground truth" below). The
   data refuted several assumptions — recorded honestly here so the next reader
   inherits facts, not guesses.
3. **v1 scope is locked to GitHub-derived data only.** No "Talk" nodes: there is
   **no structured talk dataset anywhere** (`meetup_api_scraper` scrapes the
   Meetup API *docs* into an OpenAPI file — it holds zero Adventures-In event
   data; `adventures_in_meetups` has no event model). A "talk" as speaker→topic
   is not machine-derivable from GitHub *or* the Meetup API. Talks, if ever
   wanted, are a human-authored layer or a separate second peer — out of scope
   for the graph that "draws itself."

## Verified ground truth (queried 2026-07-31, `adventures-in` org)

- **Person payload** (`GET /users/{login}`): `login`, `id` (stable numeric),
  `node_id`, `type` (`"User"` | `"Bot"`), `name`, `avatar_url`, `html_url`.
- **`type` distinguishes humans from agents at the source.** `dependabot[bot]`
  returns `"type": "Bot"`; humans return `"type": "User"`. The human/agent
  distinction the whole agent-as-peer thesis rests on is *already in the data* —
  a bot is a node whether we plan for it or not.
- **Contribution is per-repo and weighted** (`GET /repos/{o}/{r}/contributors`):
  each contributor carries `login`, `id`, and `contributions` (commit count for
  that repo). Example: `tech-world` → nickmeinhold (69), dependabot[bot] (3),
  pendashteh (1).
- **PR-review edges are EMPTY on this repo.** Merged PRs #13/#14/#15 all have
  `author=nickmeinhold`, zero reviewers — the code review here is done by AI
  models via the `/cage-match` skill, not GitHub PR reviews. So a
  `Person↔Person "co-reviewed a PR"` edge has **no data behind it**. The real
  collaboration signal is **co-contribution to a shared repo**.
- **The community is hub-and-spoke.** `chat_app` has 6 human contributors
  (nickmeinhold, Jei, gaslitbytech, adventuresin, orangegrove1955, jt535); almost
  every other repo is solo-nickmeinhold or bot-only. Drawn honestly, the graph
  *shows* Nick as the cut-vertex — `subtract-the-cut-vertex` made visible on real
  data, not a contrived demo.

## The schema

### Nodes

**`Person`** — `id = "gh:<numeric id>"` (e.g. `gh:1059276`)

| merge unit | authority | payload fields | source |
|---|---|---|---|
| `profile` | agent | `login`, `name`, `avatarUrl`, `htmlUrl`, `kind` (`User`\|`Bot`) | `GET /users/{login}` (`type`→`kind`) |
| `geometry` | human | `left`, `top`, `right`, `bottom` | canvas drag |
| `curation` | human | `displayLabel`, `hidden`, `pinned` | human edit |

**`Repo`** — `id = "repo:<numeric id>"`

| merge unit | authority | payload fields | source |
|---|---|---|---|
| `meta` | agent | `name`, `fullName`, `description`, `htmlUrl`, `pushedAt` | `GET /repos/{o}/{r}` |
| `geometry` | human | `left`, `top`, `right`, `bottom` | canvas drag |
| `curation` | human | `displayLabel`, `hidden`, `pinned` | human edit |

### Edges (the primary, non-empty relationship)

**`contribution`** — `Person → Repo`, `id = "contrib:<personId>:<repoId>"`

| merge unit | authority | payload fields | source |
|---|---|---|---|
| `weight` | agent | `commits` | contributors endpoint |

`Person↔Person` "who should meet whom" is a **derived projection** of the
bipartite contribution graph (two people connected iff they share a repo), **not
a stored edge** in v1 — it is computable from the contribution edges, and the raw
GitHub signal for it (co-review) is empty. Materializing it (as a rendered hint
or an agent-laid "gap" edge) is a v1.1 decision, deferred until the bipartite
graph is live.

## The three decisions

**Decision 1 — Merge-unit partition by AUTHORITY, not by field type.** Every node
splits its units into orthogonal ownership lanes: **agent-owned** facts
(`profile`/`meta`/`weight`) and **human-owned** presentation (`geometry`,
`curation`). Because agent-writes and human-writes land on *different* units,
LWW-per-unit makes concurrent editing conflict-free **by construction**: the
agent bumps a commit count live *while* a human drags the node, and both survive.
This is the agent-as-peer thesis proven in the grain itself, and it generalizes —
a future *layout* agent owning `geometry` as a third authority gives multi-agent
choreography for free.

**Decision 2 — The agent writes TOTALS, not deltas (idempotent snapshots).** The
agent LWW-writes the *current* aggregate (`commits: 69`), never `commits += 1`.
Replaying the same GitHub events is then a no-op, so we need **no PN-Counter
CRDT** — plain per-unit LWW suffices. GitHub is the source of truth; the canvas is
a projection of it. Per `sot_symmetric_deletion`, this is symmetric and total: a
repo/person removed from GitHub must **tombstone** its node (absence in the SoT
propagates to deletion downstream), not leave a stale orphan.

**Decision 3 — Immutable, source-prefixed ids; mutable display is a unit.** Node
id is the GitHub **numeric** id (`gh:1059276`, `repo:<id>`), never the login or
`owner/name`. This corrects ADR-0002, which keyed `Person` on `login` and `Repo`
on `owner/name` — both **mutable**, so a GitHub rename would spawn a phantom node
or collide two identities (`identity-as-mutable-key`). The source prefix (`gh:`)
namespaces the origin so a future second peer (e.g. Meetup) cannot collide ids
even for the same human. Display name lives in the mutable `profile`/`curation`
unit. Edge ids are deterministic from endpoints so re-derivation is idempotent by
id.

## v1 scope boundary (what this ADR deliberately excludes)

- **No talks / no second data source.** GitHub only. (See §"What changed" #3.)
- **No stored Person↔Person edges.** Bipartite Person—Repo only; co-contribution
  is a derived view.
- **One agent peer.** A single GitHub-reading origin. A second peer (Meetup, or
  the gap-hunter that lays "who should meet whom" edges) is a later movement.

## Open questions (named, not skated)

1. **Layout of a live-growing graph.** The agent must place a new node at
   create-time, but must never fight a human's subsequent drag. Resolution
   follows from Decision 1 (geometry is human-owned): the agent stamps `geometry`
   *once* at create with a cheap deterministic seed position and never again;
   humans (or a dedicated layout peer) own arrangement thereafter. The seed
   layout algorithm itself is unspecified here.
2. **Poll vs webhook ingestion.** ADR-0002's loop assumed either. v1 can start
   with a polled snapshot (simplest, idempotent by Decision 2); webhooks are an
   optimization, not a correctness requirement.
3. **Trust boundary.** Inherited unchanged from ADR-0002 §2 — per-unit `origin`
   already makes trust a read-time policy over origins. Not re-litigated here.
