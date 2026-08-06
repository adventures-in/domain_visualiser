import 'class_box_schema.dart' show humanOwnedUnits;
import 'container_schema.dart';
import 'graph_envelope.dart';

/// Merge-unit schemas for the community graph's typed nodes — `Person` and
/// `Repo` (ADR-0003), the payoff of the type-aware read path (#2432).
///
/// **The shared-unit invariant (DESIGN Law 4 / F-C).** Every typed schema spreads
/// [humanOwnedUnits] (`geometry` + `label`) and wraps with [withContainerUnits],
/// so the human-owned units are BYTE-IDENTICAL to `classBoxSchema`. This is what
/// makes a human's position and node name survive independently of the agent-
/// owned units: `geometry`/`label`/`parent`/`containerType`/`zIndex` merge under
/// the same names on a Person as on a ClassBox, while the agent's GitHub facts
/// live under their own unit (`profile` / `meta`). `community_schemas_test.dart`
/// asserts the shared set is deep-equal across all three registered schemas.
///
/// **Authority partition.** The agent-owned unit (`profile`/`meta`) carries facts
/// only the ingest agent knows (GitHub login, avatar, commit-derived metadata);
/// the human-owned units carry what a person edits on the canvas (drag = geometry,
/// rename = label, reparent/order = container units). They are separate merge
/// units so an agent refresh never clobbers a human drag and vice-versa.

/// `Person` — a GitHub contributor node. Agent-owned facts under `profile`; the
/// human-visible display name rides the shared `label` unit (NOT `profile`), so a
/// human rename and an agent profile refresh never contend. `login` is the stable
/// GitHub handle; `kind` distinguishes `User`/`Bot`/`Organization`.
final NodeSchema personSchema = withContainerUnits(const NodeSchema(
  type: 'Person',
  mergeUnits: {
    ...humanOwnedUnits,
    'profile': ['login', 'avatarUrl', 'htmlUrl', 'kind'],
  },
));

/// `Repo` — a GitHub repository node. Agent-owned facts under `meta`; the human-
/// visible name rides the shared `label` unit. `fullName` is `owner/name`.
final NodeSchema repoSchema = withContainerUnits(const NodeSchema(
  type: 'Repo',
  mergeUnits: {
    ...humanOwnedUnits,
    'meta': ['fullName', 'description', 'htmlUrl', 'pushedAt'],
  },
));
