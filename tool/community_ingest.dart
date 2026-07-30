// A headless **re-runnable agent peer** (`origin = agent-github`) that projects
// the `adventures-in` GitHub org into the live codraw canvas as `ClassBox`
// nodes — the ADR-0003 "Person-as-ClassBox stepping stone". It reuses the proven
// read path (everything renders as a ClassBox today) so the community graph
// appears NOW; the proper Person/Repo/Edge types are a separate increment.
//
// WHY THIS IS NOT `agent_draw.dart`: a community ingest RE-RUNS (it polls
// GitHub), whereas `agent_draw` is a one-shot seed whose full-document PATCH
// would clobber a human's edits on every re-run. This tool honours the ADR-0003
// authority partition — the agent owns FACTS (the `label` unit: a person's login
// / a repo's name), the human owns GEOMETRY (position + size). So:
//   * 404 (new node)      → CREATE: full envelope incl. a seed geometry, all
//                           stamped by agent-github.
//   * exists (seen node)  → UPDATE: a masked PATCH covering ONLY `name` and its
//                           stamp path `_envelope.stamps.label`, OMITTING
//                           left/top/right/bottom AND `_envelope.stamps.geometry`
//                           — so a human's drag survives every poll.
//
// v1 SIMPLIFICATION (flagged, not silently shipped): box SIZE encodes commit
// count at CREATE time only. Size is geometry (human-owned), so it is not
// re-touched on update — a person committing more later will NOT resize their
// existing box. A live commit-count display awaits the proper-types renderer
// (increment 2, already tracked). Bots (type==Bot) are skipped for v1 clarity;
// they are real nodes deferred to the same increment.
//
// TWO TARGETS (same split as agent_draw):
//   dart run tool/community_ingest.dart          # local Firestore emulator
//   dart run tool/community_ingest.dart --live    # the real domain-visualiser-app
//
// DATA SOURCE: `gh api` via Process.run — reuses Nick's gh auth, keeps tokens
// off argv/env, mirrors agent_draw's gcloud-via-Process pattern.
//
// Pure Dart + `dart:io` only (no `http` dep, no Flutter engine).

import 'dart:convert';
import 'dart:io';

import 'package:domain_visualiser/graph/agent_draw_envelope.dart';
import 'package:domain_visualiser/graph/class_box_schema.dart' show envelopeKey;
import 'package:domain_visualiser/graph/community_projection.dart';
import 'package:domain_visualiser/graph/hlc_manager.dart';

import 'firestore_rest.dart';

const String _origin = 'agent-github';
const String _org = 'adventures-in';

Future<void> main(List<String> args) async {
  final target = await resolveTarget(args);
  final hlc = HlcManager(nodeId: _origin);
  final client = HttpClient();

  // Preflight: fail fast with a clear message if the target isn't reachable.
  try {
    await read(client, target, 'preflight-probe');
  } on SocketException {
    stderr.writeln('Cannot reach ${target.label}.\n'
        'Emulator: start it first (see this file\'s header).');
    client.close();
    exitCode = 1;
    return;
  }

  // 1. Pull the org from GitHub (facts).
  stdout.writeln('agent "$_origin" fetching $_org from GitHub via gh…');
  final repos = await _fetchRepos();
  final contributorsByRepo = <String, List<GhContributor>>{};
  for (final r in repos) {
    if (r.fork) continue; // forks are excluded — don't spend API calls on them
    contributorsByRepo[r.name] = await _fetchContributors(r.name);
  }

  // 2. Project to canvas boxes (pure, deterministic).
  final projection = projectCommunity(
    repos: repos,
    contributorsByRepo: contributorsByRepo,
  );
  final people = projection.people.toList();
  final repoBoxes = projection.repos.toList();
  stdout.writeln('projected ${repoBoxes.length} repo + ${people.length} person '
      '= ${projection.boxes.length} boxes');
  for (final note in projection.capNotes) {
    stdout.writeln('  cap: $note');
  }
  final biggest =
      people.isEmpty ? null : people.reduce((a, b) => a.commits >= b.commits ? a : b);
  if (biggest != null) {
    stdout.writeln('  largest box: ${biggest.name} '
        '(${biggest.commits} commits, ${biggest.width.toStringAsFixed(0)}px)');
  }

  // 3. Write each box, create-vs-update so human geometry is never clobbered.
  stdout.writeln('\nwriting → ${target.label}…');
  var created = 0, updated = 0, unchanged = 0;
  for (final box in projection.boxes) {
    final existing = await read(client, target, box.id);
    if (existing == null) {
      // CREATE: full envelope, agent stamps geometry (seed) + label. ATOMIC via
      // currentDocument.exists=false — if the doc appeared between the read above
      // and now (an overlapping poll, or a human dragging a just-created node),
      // the create fails closed and we fall back to a masked update rather than
      // full-PATCH-clobbering the human's geometry.
      final doc = agentClassBoxDoc(
        hlc: hlc,
        origin: _origin,
        left: box.left,
        top: box.top,
        right: box.right,
        bottom: box.bottom,
        name: box.name,
        userId: _origin,
      );
      if (await createIfAbsent(client, target, box.id, doc)) {
        created++;
      } else {
        // Raced: doc existed at create-time — re-read and update its label only.
        final now = await read(client, target, box.id);
        if (now != null) {
          if (await _writeLabelUpdate(client, target, hlc, box.id, box.name, now)) {
            updated++;
          } else {
            unchanged++;
          }
        } else {
          // 409-then-404: a concurrent delete raced between the failed create and
          // this re-read. Don't silently undercount — surface it. Harmless: the
          // node is idempotently re-created on the next poll.
          stderr.writeln('  WARN ${box.id}: create precondition failed but doc '
              'then absent (concurrent delete?) — skipped, will re-create next poll');
        }
      }
    } else {
      if (await _writeLabelUpdate(client, target, hlc, box.id, box.name, existing)) {
        updated++;
      } else {
        unchanged++;
      }
    }
  }

  // Readback: GET every projected id so the run PROVES the intended set landed
  // (verify, don't assert — the same discipline agent_draw uses).
  var present = 0;
  for (final box in projection.boxes) {
    if (await read(client, target, box.id) != null) present++;
  }
  stdout.writeln('\nreadback: $present/${projection.boxes.length} projected '
      'nodes present in ${target.label}.');
  if (present != projection.boxes.length) {
    stderr.writeln('  WARN readback short — some nodes did not land; a re-run '
        'will idempotently reconcile.');
  }

  // KNOWN LIMITATION (tracked: issue #17) — this ingest enforces PRESENCE but not
  // ABSENCE. A node whose GitHub basis disappears (repo drops below 2 humans, a
  // person leaves) is never tombstoned, so a stale gh-* box lingers. ADR-0003
  // Decision 2 (sot_symmetric_deletion) wants that tombstoned; it is a separate
  // increment (enumerate live gh-* docs, diff against the projection, tombstone
  // the absent). v1-acceptable: this org's node set only grows in practice.

  stdout.writeln('\ndone — $created created, $updated updated, $unchanged '
      'unchanged (no-op) on ${target.label}.');
  client.close();
}

/// UPDATE the agent-owned `label` unit only, IF it actually changed. Returns true
/// if a write was issued, false if skipped (a genuine no-op or the doc vanished).
///
/// IDEMPOTENT SNAPSHOTS (ADR-0003 Decision 2): replaying the same GitHub facts
/// must be a no-op. So when the existing doc already carries this name AND its
/// label stamp is already ours (`agent-github`), we write NOTHING — bumping the
/// HLC every poll would dirty the envelope and make every subscribed canvas
/// re-project 16 boxes for zero fact change (a continuous re-render feed). We
/// still re-write when the name changed OR the label stamp is missing/foreign (a
/// fact to (re)assert). Observes the existing stamps first so a real write sorts
/// strictly after them; the masked PATCH omits geometry, so a human drag/resize
/// survives, and its existence-precondition means it can never create a partial
/// doc if the row vanished mid-flight.
Future<bool> _writeLabelUpdate(HttpClient client, FirestoreTarget target,
    HlcManager hlc, String id, String name,
    Map<String, Object?> existing) async {
  final fields = existing['fields'] as Map?;
  final currentName = (fields?['name'] as Map?)?['stringValue'];
  final labelOrigin = _labelStampOrigin(existing);
  if (currentName == name && labelOrigin == _origin) {
    return false; // no-op: facts unchanged and we already own the label
  }
  for (final h in _stampHlcs(existing)) {
    if (HlcManager.isValidHlc(h)) hlc.observe(h);
  }
  final update = agentLabelUpdateDoc(hlc: hlc, origin: _origin, name: name);
  return patchMasked(client, target, id, update.doc, update.fieldPaths);
}

/// The origin of the `label` stamp on a read doc (Firestore REST shape), or null.
String? _labelStampOrigin(Map<String, Object?> doc) {
  final env = _mapVal((doc['fields'] as Map?)?[envelopeKey]);
  final stamps = _mapVal(env?['stamps']);
  final label = _mapVal(stamps?['label']);
  return (label?['origin'] as Map?)?['stringValue'] as String?;
}

// --- GitHub via gh (facts source) --------------------------------------------

/// Runs `gh api --paginate <path> --jq <filter>` and returns each emitted line
/// as a decoded JSON object. `--jq '.[] | {…}'` streams array elements as
/// newline-delimited JSON (JSONL), so pagination and large arrays are handled
/// without hand-rolling Link-header parsing.
Future<List<Map<String, dynamic>>> _ghJsonl(String path, String jq) async {
  final r = await Process.run('gh', ['api', '--paginate', path, '--jq', jq]);
  if (r.exitCode != 0) {
    final err = (r.stderr as String).trim();
    // An empty repo's contributors endpoint 204s; gh treats it as no content.
    // Surface everything else loudly rather than silently dropping data.
    throw StateError('gh api $path failed (exit ${r.exitCode}): $err');
  }
  final out = (r.stdout as String).trim();
  if (out.isEmpty) return const [];
  return out
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .map((l) => jsonDecode(l) as Map<String, dynamic>)
      .toList();
}

Future<List<GhRepo>> _fetchRepos() async {
  final rows =
      await _ghJsonl('orgs/$_org/repos?per_page=100', '.[] | {name,id,fork}');
  return rows
      .map((m) => GhRepo(
            name: m['name'] as String,
            id: (m['id'] as num).toInt(),
            fork: m['fork'] as bool,
          ))
      .toList();
}

Future<List<GhContributor>> _fetchContributors(String repo) async {
  // Empty result = a genuinely-empty repo (204) OR a transient 202 while GitHub
  // computes contributor stats on a cold repo — both yield []. That transiently
  // models the repo as 0-contributors, so it may be excluded this poll. This is
  // eventual, NOT data loss: the ingest is idempotent and re-runs (Decision 2),
  // so on the next poll the warm endpoint returns real data and the missing
  // nodes get CREATEd then. A truly missing repo would exit non-zero and throw.
  final rows = await _ghJsonl('repos/$_org/$repo/contributors?per_page=100',
      '.[] | {login,id,type,contributions}');
  return rows
      .map((m) => GhContributor(
            login: m['login'] as String,
            id: (m['id'] as num).toInt(),
            type: GhContributorType.fromApi(m['type'] as String),
            contributions: (m['contributions'] as num).toInt(),
          ))
      .toList();
}

// --- Firestore REST value navigation -----------------------------------------

/// Extracts every stamp HLC string from a document returned by [read] (the
/// Firestore REST `Value` shape). Used so an UPDATE observes the doc's existing
/// clocks before minting a strictly-later label stamp.
List<String> _stampHlcs(Map<String, Object?> doc) {
  final result = <String>[];
  final fields = doc['fields'] as Map?;
  final env = _mapVal(fields?[envelopeKey]);
  final stamps = _mapVal(env?['stamps']);
  if (stamps == null) return result;
  for (final unit in stamps.values) {
    final hlc = (_mapVal(unit)?['hlc'] as Map?)?['stringValue'];
    if (hlc is String) result.add(hlc);
  }
  return result;
}

/// Unwraps a Firestore REST `mapValue` into its inner `fields` map, or null.
Map<String, Object?>? _mapVal(Object? v) {
  if (v is! Map) return null;
  final fields = (v['mapValue'] as Map?)?['fields'];
  return fields is Map ? Map<String, Object?>.from(fields) : null;
}
