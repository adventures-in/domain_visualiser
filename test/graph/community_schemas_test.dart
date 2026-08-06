import 'package:codraw/graph/class_box_schema.dart';
import 'package:codraw/graph/community_schemas.dart';
import 'package:codraw/graph/graph_envelope.dart';
import 'package:codraw/graph/hlc_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// Slice 1 (#2432): the typed community schemas (`Person`/`Repo`) and the
/// shared-human-owned-unit invariant that keeps a human's geometry/label/hierarchy
/// byte-identical across every node type (DESIGN Law 4 / round-2 finding F-C).
void main() {
  // The units a human authors on the canvas — must be declared IDENTICALLY on
  // every node type, else reading a doc under a sibling schema silently drops the
  // human's edit (`_mergeUnits` carries only fields of *declared* units).
  const sharedHumanUnits = ['geometry', 'label', 'parent', 'containerType', 'zIndex'];

  group('shared human-owned unit invariant (Law 4 / F-C)', () {
    for (final unit in sharedHumanUnits) {
      test('unit "$unit" is byte-identical across ClassBox / Person / Repo', () {
        final cb = classBoxSchema.mergeUnits[unit];
        final person = personSchema.mergeUnits[unit];
        final repo = repoSchema.mergeUnits[unit];
        expect(cb, isNotNull, reason: 'ClassBox must declare "$unit"');
        expect(person, equals(cb),
            reason: 'Person "$unit" must equal ClassBox "$unit" (no drift)');
        expect(repo, equals(cb),
            reason: 'Repo "$unit" must equal ClassBox "$unit" (no drift)');
      });
    }
  });

  group('agent-owned units (authority partition)', () {
    test('Person carries a profile unit ClassBox/Repo do not', () {
      expect(personSchema.mergeUnits['profile'],
          equals(['login', 'avatarUrl', 'htmlUrl', 'kind']));
      expect(classBoxSchema.mergeUnits.containsKey('profile'), isFalse);
      expect(repoSchema.mergeUnits.containsKey('profile'), isFalse);
    });

    test('Repo carries a meta unit ClassBox/Person do not', () {
      expect(repoSchema.mergeUnits['meta'],
          equals(['fullName', 'description', 'htmlUrl', 'pushedAt']));
      expect(classBoxSchema.mergeUnits.containsKey('meta'), isFalse);
      expect(personSchema.mergeUnits.containsKey('meta'), isFalse);
    });

    test('ClassBox UML list units are NOT on Person/Repo', () {
      for (final u in ['staticMethods', 'instanceMethods']) {
        expect(classBoxSchema.mergeUnits.containsKey(u), isTrue);
        expect(personSchema.mergeUnits.containsKey(u), isFalse);
        expect(repoSchema.mergeUnits.containsKey(u), isFalse);
      }
    });
  });

  // The whole reason the registry is load-bearing on READ, not just paint (DESIGN
  // claim-to-falsify #1 / T5): merging a Person under its OWN schema carries the
  // agent-owned profile fields; merging it under the wrong schema would advance
  // the stamp but DROP the fields. This proves the profile survives a real merge.
  test('a Person merges under personSchema WITHOUT losing profile fields', () {
    final hlc = HlcManager(nodeId: 'author');
    FieldStamp stamp() => FieldStamp(hlc: hlc.issue(), origin: 'author');

    final local = GraphNode(
      id: 'gh:1',
      type: 'Person',
      payload: const {
        'login': 'ada',
        'avatarUrl': 'https://x/a.png',
        'htmlUrl': 'https://github.com/ada',
        'kind': 'User',
        'name': 'Ada Lovelace',
        'left': 0.0,
        'top': 0.0,
        'right': 100.0,
        'bottom': 60.0,
      },
      stamps: {'profile': stamp(), 'label': stamp(), 'geometry': stamp()},
    );
    // A later remote drag: only geometry moves (higher HLC).
    final remote = GraphNode(
      id: 'gh:1',
      type: 'Person',
      payload: const {
        'left': 10.0,
        'top': 10.0,
        'right': 110.0,
        'bottom': 70.0,
      },
      stamps: {'geometry': stamp()},
    );

    final merged = mergeNodes(local, remote, personSchema);

    // Geometry took the later drag...
    expect(merged.payload['left'], 10.0);
    // ...and the agent-owned profile fields SURVIVED (the field-loss #2432 closes).
    expect(merged.payload['login'], 'ada');
    expect(merged.payload['avatarUrl'], 'https://x/a.png');
    expect(merged.payload['kind'], 'User');
    expect(merged.payload['name'], 'Ada Lovelace');
  });
}
