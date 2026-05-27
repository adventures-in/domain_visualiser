# ADR-0002 — Agent-as-peer, and the GitHub-push community map as its first test case

- **Status:** Proposed (dream banked as structure — 2026-05-27)
- **Date:** 2026-05-27
- **Builds on:** ADR-0001 (the generic envelope)
- **Concept:** `~/.claude/projects/-Users-nick-git/memory/concept_agent_as_crdt_peer.md`

## The realization

There is no "agent-as-peer feature" to design. A CRDT writer is just an
**origin + HLC**, and the merge math (`mergeNodes`, ADR-0001) contains *no
human-specific assumption* — `FieldStamp.origin` carries a client id, nothing
more. So an AI agent writing stamped `GraphNode`s into the same transport the
humans use **is** a peer, and the existing merge converges its edits with
theirs. The human path and the agent path are the same path.

An agent-peer therefore needs exactly two things, and we already have one:

1. **a client id** — done (`origin`); an agent's `HlcManager` is seeded with its
   own nodeId, same as any client.
2. **a transport** — the `GraphSyncBackend` seam (the thing we were already
   going to build for the humans). The agent writes to the same Firestore
   collection the canvas reads.

## The first test case: a community map that updates from GitHub pushes

Chosen because it is a *real* data source (not synthetic), it exercises
agent-as-peer end to end, and it is demo-able in the AMR/Imagineering room — the
community's own graph, redrawing itself live while people watch.

**The loop:**
1. Agent polls a GitHub org (or receives webhooks) for push/repo/member events.
2. It diffs against last-seen state → produces a changeset of `GraphNode`s
   (and edges — see Open Question 1).
3. It stamps each merge unit with `origin = <agent-client-id>` and a fresh HLC.
4. It writes to the transport the canvas already reads.
5. The canvas merges via `mergeNodes`; nodes **appear live alongside human
   edits**, conflict-free.

**GitHub → GraphNode mapping (concrete):**

| GitHub entity | `type` | `id` | merge units |
|---|---|---|---|
| Repository | `Repo` | `owner/name` | `meta`={description, language, pushedAt}, `popularity`={stars, forks} |
| User | `Person` | login | `profile`={name, avatarUrl, bio} |
| Organization | `Org` | login | `profile`={name, avatarUrl} |

The seed dataset already exists (the Melbourne AI-builder community: `org_amr`,
`project_imagineering`, the `user_collaborator_*` people; a read-only mock at
`~/Downloads/community-graph.html`).

## Open questions this test case forces (named, not skated)

1. **Edges are not yet first-class.** ADR-0001 shipped `GraphNode` only; the
   community map is *all about edges* (`Person —contributes-to→ Repo`,
   `Repo —belongs-to→ Org`). Decision needed: edge-as-`GraphNode` (type=`edge`,
   `src`/`dst` in payload, existence as an OR-Set-ish unit) vs. a parallel
   `GraphEdge` type. Leaning edge-as-node so one merge path covers both, but
   edge *deletion* + dangling-endpoint semantics need thought. **This is the
   next envelope increment.**

2. **The trust boundary — the asterisk we won't romanticize past.** The merge
   converges a malicious or hallucinated agent edit just as happily as a good
   one. Conflict-*free* ≠ *trusted*. Three layers, cheapest first:
   - **Provenance is already free.** Every merge unit carries `origin`, so
     "who asserted this" is *already queryable per field*. Trust becomes a
     **read-time policy over origins**, not new write machinery — render
     agent-origin nodes differently, filter by trusted origin set.
   - **Acceptance as a human-origin write.** Agent edits land in a "proposed"
     state; a human accepting is just a higher-HLC human-origin stamp that wins
     LWW. CRDT-native, no new mechanism.
   - **Transport-enforced** (later): Firestore security rules / signed origins
     gate which origins may write which fields. The real boundary for a shared
     MQTT bus (Aiko).

   The elegant through-line: **the envelope's per-unit `origin` already turns
   trust from a write-time gate into a read-time policy.** We get provenance for
   free and *choose* how much to enforce.

## The other two scenes (banked, not chosen)

- **Engram curiosity-gap glow** — the agent lays glowing gap-nodes while you
  study. Best *product* loop (next brainstorm).
- **Peer Claudes co-editing the memory graph** — dogfood: the memory dir is
  already a graph, peer-instance-collision is already a live bug
  (`feedback_peer_instance_collisions`), and CRDT **inverts the bug into the
  feature**. The recursion becomes the test environment.

## Consequence

Agent-as-peer is not a milestone after the human canvas — it is the *same*
milestone. Building the `GraphSyncBackend` seam for humans delivers the agent
substrate simultaneously. This is the literal form of Andy Gelme's "communities
of communities with AI agents as members, not instruments."
