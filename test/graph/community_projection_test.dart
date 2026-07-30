import 'dart:convert';
import 'dart:io';

import 'package:domain_visualiser/graph/community_projection.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the FIXED captured GitHub fixture and parses it into the projection's
/// input records. No network — the tool fetches live via `gh`, the test replays
/// bytes (cf. self-referential-codec blindness: the *output* is proven
/// consumable by the separate acceptance test through the real FirestoreBackend).
({List<GhRepo> repos, Map<String, List<GhContributor>> contributors})
    _loadFixture() {
  final raw = jsonDecode(
      File('test/fixtures/github_community.json').readAsStringSync()) as Map;
  final repos = (raw['repos'] as List)
      .map((r) => GhRepo(
            name: r['name'] as String,
            id: (r['id'] as num).toInt(),
            fork: r['fork'] as bool,
          ))
      .toList();
  final contributors = <String, List<GhContributor>>{};
  (raw['contributors'] as Map).forEach((repo, list) {
    contributors[repo as String] = (list as List)
        .map((c) => GhContributor(
              login: c['login'] as String,
              id: (c['id'] as num).toInt(),
              type: GhContributorType.fromApi(c['type'] as String),
              contributions: (c['contributions'] as num).toInt(),
            ))
        .toList();
  });
  return (repos: repos, contributors: contributors);
}

void main() {
  group('projectCommunity', () {
    late CommunityProjection p;
    setUp(() {
      final f = _loadFixture();
      p = projectCommunity(repos: f.repos, contributorsByRepo: f.contributors);
    });

    test('includes only non-fork repos with >=2 human contributors', () {
      final repoNames = p.repos.map((b) => b.name).toSet();
      expect(repoNames, {'chat_app', 'tech-world'});
      // podcustard is solo → out; dart-pad is a fork → out even with 2 humans.
      expect(repoNames, isNot(contains('podcustard')));
      expect(repoNames, isNot(contains('dart-pad')));
    });

    test('repo ids are source-prefixed numeric ids (immutable, ADR-0003 D3)', () {
      final ids = p.repos.map((b) => b.id).toSet();
      expect(ids, {'gh-repo-100', 'gh-repo-101'});
    });

    test('includes every person on an included repo, skips bots and fork-only',
        () {
      final personIds = p.people.map((b) => b.id).toSet();
      // nick(1), Jei(2), pendashteh(3) — all on an included repo.
      expect(personIds, {'gh-person-1', 'gh-person-2', 'gh-person-3'});
      // dependabot[bot] (99) is a Bot → skipped.
      expect(personIds, isNot(contains('gh-person-99')));
      // some-googler (50) contributes only to the fork → not a community node.
      expect(personIds, isNot(contains('gh-person-50')));
    });

    test('person commits aggregate across NON-FORK org repos only', () {
      final nick = p.people.firstWhere((b) => b.id == 'gh-person-1');
      // 40 (chat_app) + 29 (tech-world) + 10 (podcustard) = 79. The fork's 5 do
      // NOT count.
      expect(nick.commits, 79);
      expect(p.people.firstWhere((b) => b.id == 'gh-person-2').commits, 19);
      expect(p.people.firstWhere((b) => b.id == 'gh-person-3').commits, 1);
    });

    test('the cut-vertex is the largest box (size encodes commits)', () {
      final byCommits = p.people.toList()
        ..sort((a, b) => b.commits.compareTo(a.commits));
      final nick = byCommits.first;
      expect(nick.id, 'gh-person-1');
      // Strictly larger than everyone else.
      for (final other in p.people.where((b) => b.id != nick.id)) {
        expect(nick.width, greaterThan(other.width),
            reason: '${nick.name} should be bigger than ${other.name}');
      }
      // Person boxes are square (size is the one relational signal).
      expect(nick.width, closeTo(nick.height, 0.001));
    });

    test('cap notes account for every exclusion (never silent truncation)', () {
      final joined = p.capNotes.join(' | ');
      expect(joined, contains('fork'));
      expect(joined, contains('dart-pad'));
      expect(joined, contains('bot'));
      // 1 non-fork solo repo (podcustard) excluded.
      expect(joined, contains('<2 human'));
    });

    test('layout is deterministic and non-overlapping', () {
      // Re-run: identical geometry (stable sort by numeric id).
      final f = _loadFixture();
      final p2 =
          projectCommunity(repos: f.repos, contributorsByRepo: f.contributors);
      for (var i = 0; i < p.boxes.length; i++) {
        expect(p2.boxes[i].id, p.boxes[i].id);
        expect(p2.boxes[i].left, p.boxes[i].left);
        expect(p2.boxes[i].top, p.boxes[i].top);
      }
      // No two boxes overlap (axis-aligned rectangle intersection test).
      bool overlap(CommunityBox a, CommunityBox b) =>
          a.left < b.right &&
          b.left < a.right &&
          a.top < b.bottom &&
          b.top < a.bottom;
      for (var i = 0; i < p.boxes.length; i++) {
        for (var j = i + 1; j < p.boxes.length; j++) {
          expect(overlap(p.boxes[i], p.boxes[j]), isFalse,
              reason: '${p.boxes[i].id} overlaps ${p.boxes[j].id}');
        }
      }
    });

    test('repos band sits above the people band (proximity/relational hint)', () {
      final repoBottom =
          p.repos.map((b) => b.bottom).reduce((a, b) => a > b ? a : b);
      final peopleTop =
          p.people.map((b) => b.top).reduce((a, b) => a < b ? a : b);
      expect(peopleTop, greaterThan(repoBottom));
    });
  });
}
