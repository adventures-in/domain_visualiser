import 'dart:math' as math;

/// Pure, network-free projection of the `adventures-in` GitHub org into a set of
/// canvas boxes — the "stepping stone" that reuses the existing `ClassBox` type
/// (ADR-0003) so the community graph renders TODAY through the proven read path.
///
/// This file deliberately holds NO I/O: `tool/community_ingest.dart` fetches the
/// GitHub JSON (via `gh api` through `Process.run`) and hands the parsed records
/// here; the unit tests feed a FIXED captured fixture. Same function, same bytes,
/// no network in tests (cf. self-referential-codec blindness — the acceptance
/// test proves the *output* bytes are consumable via the real `FirestoreBackend`).
///
/// Projection rules (ADR-0003, v1 stepping stone):
///  - One box per Repo with >=2 human contributors that is NOT a fork. Forks
///    (`dart-pad`, `dart-services`) carry upstream dart-lang contributor history
///    that is not community collaboration — including them would swamp the graph
///    with ~50 external Google committers, so they are the documented cap.
///  - One box per Person (`type == "User"`) who contributes to any INCLUDED repo.
///    Bots (`type == "Bot"`, e.g. `dependabot[bot]`) are skipped for v1 clarity —
///    they are real nodes and the proper-types renderer (increment 2) will draw
///    them; noted here so the omission is deliberate, not forgotten.
///  - Person box SIZE encodes total commit count across all non-fork org repos
///    (bigger = more commits), so the cut-vertex (nickmeinhold, in nearly every
///    collaborative repo) is visibly the largest box. Since edges and method
///    lists do not render yet, size is the one relational visual signal.

/// A GitHub repository record (the subset the projection needs).
class GhRepo {
  const GhRepo({required this.name, required this.id, required this.fork});
  final String name;
  final int id;
  final bool fork;
}

/// The GitHub account kind for a contributor. A closed set at the source
/// (`GET /repos/.../contributors` returns `"User"` or `"Bot"`), so it is an
/// enum, not a raw `String` — a typo like `'uesr'` can't compile. [other] is a
/// defensive catch-all for an unexpected future value so parsing never throws.
enum GhContributorType {
  user,
  bot,
  other;

  /// Maps the GitHub API `type` string onto the enum. Unknown → [other].
  static GhContributorType fromApi(String raw) => switch (raw) {
        'User' => user,
        'Bot' => bot,
        _ => other,
      };
}

/// A GitHub contributor record for one repo (from `/repos/{o}/{r}/contributors`).
class GhContributor {
  const GhContributor({
    required this.login,
    required this.id,
    required this.type,
    required this.contributions,
  });
  final String login;
  final int id;
  final GhContributorType type;
  final int contributions;

  bool get isHuman => type == GhContributorType.user;
}

/// A projected canvas box (Person or Repo), carrying its seed geometry.
///
/// [id] is the immutable, source-prefixed node id (ADR-0003 Decision 3):
/// `gh-person-<numericId>` / `gh-repo-<numericId>` — the GitHub numeric id, never
/// the mutable login / `owner/name`. Hyphen-separated (not `gh:` colon) because
/// this id is also a Firestore document id.
class CommunityBox {
  const CommunityBox({
    required this.id,
    required this.name,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.isPerson,
    required this.commits,
  });

  final String id;
  final String name;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final bool isPerson;

  /// Total commits (persons only; 0 for repos). Encoded as box size at CREATE
  /// time — see [CommunityProjection] v1 note.
  final int commits;

  double get width => right - left;
  double get height => bottom - top;
}

/// The full projection result: the boxes plus a human-readable account of what
/// was capped/excluded (never a silent truncation).
class CommunityProjection {
  const CommunityProjection({required this.boxes, required this.capNotes});
  final List<CommunityBox> boxes;
  final List<String> capNotes;

  Iterable<CommunityBox> get people => boxes.where((b) => b.isPerson);
  Iterable<CommunityBox> get repos => boxes.where((b) => !b.isPerson);
}

// --- layout + sizing constants (deterministic, non-overlapping) --------------

const double _reposBandY = 60.0;
const double _repoW = 170.0;
const double _repoH = 90.0;
const double _gap = 40.0;
const double _leftMargin = 80.0;
const double _maxX = 1600.0;

// Person box side scales with sqrt(commits) so 1 vs 541 commits compresses to a
// readable spread, clamped to a sane min/max. Square boxes: size *is* the signal.
const double _personMin = 110.0;
const double _personMax = 280.0;
const double _personRef = 600.0; // ~max expected total → maps near _personMax

double _personSide(int commits) {
  final k = (_personMax - _personMin) / math.sqrt(_personRef);
  final s = _personMin + k * math.sqrt(commits.toDouble());
  return s.clamp(_personMin, _personMax);
}

/// Projects the org into canvas boxes. Deterministic: nodes are sorted by
/// numeric id so re-runs place the same node in the same seat.
CommunityProjection projectCommunity({
  required List<GhRepo> repos,
  required Map<String, List<GhContributor>> contributorsByRepo,
  int maxNodes = 40,
}) {
  final capNotes = <String>[];

  // 1. Included repos: not a fork, >= 2 human contributors.
  final forks = repos.where((r) => r.fork).map((r) => r.name).toList()..sort();
  final nonFork = repos.where((r) => !r.fork).toList();

  final included = <GhRepo>[];
  var soloOrEmpty = 0;
  for (final r in nonFork) {
    final humans =
        (contributorsByRepo[r.name] ?? const []).where((c) => c.isHuman).length;
    if (humans >= 2) {
      included.add(r);
    } else {
      soloOrEmpty++;
    }
  }
  included.sort((a, b) => a.id.compareTo(b.id));

  if (forks.isNotEmpty) {
    capNotes.add(
        'excluded ${forks.length} fork(s) [upstream contributor history, not '
        'community]: ${forks.join(', ')}');
  }
  capNotes.add(
      'excluded $soloOrEmpty non-fork repo(s) with <2 human contributors '
      '(solo or bot-only)');

  // 2. Persons: anyone (type User) contributing to an included repo. Aggregate
  //    total commits across all NON-FORK org repos (forks are not community
  //    work, so their commits do not count toward a person's size).
  final includedRepoNames = included.map((r) => r.name).toSet();
  final personTotals = <int, int>{}; // numeric id -> total commits
  final personLogin = <int, String>{};
  final includedPersonIds = <int>{};
  var botsSkipped = 0;

  for (final r in nonFork) {
    for (final c in contributorsByRepo[r.name] ?? const <GhContributor>[]) {
      if (!c.isHuman) {
        // Bots are real nodes; skipped for v1 clarity (proper-types renderer,
        // increment 2, will draw them). Count once per (repo, bot) appearance
        // only where it would otherwise have mattered — dedup below on ids.
        continue;
      }
      personTotals[c.id] = (personTotals[c.id] ?? 0) + c.contributions;
      personLogin[c.id] = c.login;
      if (includedRepoNames.contains(r.name)) includedPersonIds.add(c.id);
    }
  }
  // Distinct bots (across all non-fork repos) — reported, not drawn.
  final botIds = <int>{};
  for (final r in nonFork) {
    for (final c in contributorsByRepo[r.name] ?? const <GhContributor>[]) {
      if (!c.isHuman) botIds.add(c.id);
    }
  }
  botsSkipped = botIds.length;
  if (botsSkipped > 0) {
    capNotes.add('skipped $botsSkipped bot contributor(s) [type==Bot] — real '
        'nodes deferred to the proper-types renderer');
  }

  // Guard: if the readable-node budget is ever blown, cap persons by commit
  // count (keep the biggest contributors) and log it — never silently truncate.
  var personIds = includedPersonIds.toList()..sort();
  final repoCount = included.length;
  if (repoCount + personIds.length > maxNodes) {
    final budget = math.max(0, maxNodes - repoCount);
    personIds.sort((a, b) => (personTotals[b] ?? 0).compareTo(personTotals[a] ?? 0));
    final dropped = personIds.length - budget;
    personIds = personIds.take(budget).toList()..sort();
    // Repos are never dropped (they are the collaboration hubs), so when they
    // alone meet/exceed the budget the node count STAYS above maxNodes — say so
    // honestly rather than claiming a bound the result doesn't satisfy.
    if (budget == 0) {
      capNotes.add('CAPPED all $dropped person(s): the $repoCount included repos '
          'alone reach the $maxNodes-node budget — node count is $repoCount '
          '(repos are the hubs and are never dropped, only people are)');
    } else {
      capNotes.add('CAPPED $dropped lower-commit person(s) to keep node count '
          '<= $maxNodes (kept the $budget highest-commit contributors)');
    }
  }

  // 3. Lay out repos in a top band, people in a band below. Flow-wrap each band
  //    left-to-right; bands never overlap because the people band starts below
  //    the repos band's lowest row.
  final boxes = <CommunityBox>[];

  var x = _leftMargin;
  var y = _reposBandY;
  var rowBottom = y + _repoH;
  for (final r in included) {
    if (x + _repoW > _maxX) {
      x = _leftMargin;
      y = rowBottom + _gap;
      rowBottom = y + _repoH;
    }
    boxes.add(CommunityBox(
      id: 'gh-repo-${r.id}',
      name: r.name,
      left: x,
      top: y,
      right: x + _repoW,
      bottom: y + _repoH,
      isPerson: false,
      commits: 0,
    ));
    x += _repoW + _gap;
    rowBottom = math.max(rowBottom, y + _repoH);
  }

  // People band starts a clear gap below the repos band.
  var py = rowBottom + 2 * _gap;
  var px = _leftMargin;
  var pRowBottom = py;
  for (final pid in personIds) {
    final commits = personTotals[pid] ?? 0;
    final side = _personSide(commits);
    if (px + side > _maxX) {
      px = _leftMargin;
      py = pRowBottom + _gap;
      pRowBottom = py;
    }
    boxes.add(CommunityBox(
      id: 'gh-person-$pid',
      name: personLogin[pid] ?? 'user-$pid',
      left: px,
      top: py,
      right: px + side,
      bottom: py + side,
      isPerson: true,
      commits: commits,
    ));
    px += side + _gap;
    pRowBottom = math.max(pRowBottom, py + side);
  }

  return CommunityProjection(boxes: boxes, capNotes: capNotes);
}
