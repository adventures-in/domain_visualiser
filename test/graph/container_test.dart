import 'package:codraw/graph/class_box_schema.dart' as cbs;
import 'package:codraw/graph/container_schema.dart';
import 'package:codraw/graph/fractional_index.dart';
import 'package:codraw/graph/graph_envelope.dart';
import 'package:codraw/graph/hierarchy.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal schema with no app-level units — `withContainerUnits` layers on
/// `parent`, `containerType`, `zIndex`. This is the "container support is
/// universal" path: any schema picks it up by passing through the helper.
final NodeSchema _schema =
    withContainerUnits(const NodeSchema(type: 'Box', mergeUnits: {}));

FieldStamp _stamp(String origin, int seq) => FieldStamp(
      hlc:
          '2026-05-31T08:00:00.000Z-${seq.toString().padLeft(4, '0')}-$origin',
      origin: origin,
    );

GraphNode _node(
  String id, {
  String? parent,
  String? containerType,
  String? zIndex,
  Map<String, FieldStamp> stamps = const {},
  bool deleted = false,
}) {
  final payload = <String, Object?>{
    if (parent != null) parentField: parent,
    if (containerType != null) containerTypeField: containerType,
    if (zIndex != null) zIndexField: zIndex,
    if (deleted) NodeSchema.tombstoneField: true,
  };
  return GraphNode(id: id, type: 'Box', payload: payload, stamps: stamps);
}

void main() {
  group('withContainerUnits', () {
    test('layers the three universal units onto a base schema', () {
      final base = const NodeSchema(type: 'X', mergeUnits: {'label': ['name']});
      final layered = withContainerUnits(base);
      expect(layered.mergeUnits.keys,
          containsAll(['label', parentUnit, containerTypeUnit, zIndexUnit]));
      expect(layered.mergeUnits[parentUnit], [parentField]);
    });

    test('caller-declared units win over implicit ones', () {
      // Hypothetical: an app that grains parent+zIndex together into one unit.
      final custom = const NodeSchema(type: 'X', mergeUnits: {
        parentUnit: [parentField, zIndexField],
      });
      final layered = withContainerUnits(custom);
      expect(layered.mergeUnits[parentUnit], [parentField, zIndexField]);
      // containerType still gets added because it wasn't declared.
      expect(layered.mergeUnits[containerTypeUnit], [containerTypeField]);
    });
  });

  group('mergeNodes — container units', () {
    test('concurrent reparent on same child: higher-HLC wins, no torn state',
        () {
      final base = _node('c',
          parent: 'p0', stamps: {parentUnit: _stamp('seed', 0)});
      // Alice moves c under p1; Bob moves c under p2 with a later HLC.
      final alice = _node('c',
          parent: 'p1', stamps: {parentUnit: _stamp('alice', 1)});
      final bob = _node('c',
          parent: 'p2', stamps: {parentUnit: _stamp('bob', 2)});

      final ab = mergeNodes(alice, bob, _schema);
      final ba = mergeNodes(bob, alice, _schema);

      expect(ab.payload[parentField], 'p2', reason: 'higher HLC wins');
      expect(ba.payload[parentField], 'p2', reason: 'order-independent');
      expect(ab.stamps[parentUnit]!.origin, 'bob');
      // Sanity: the seed base would also lose to bob.
      final viaBase = mergeNodes(base, bob, _schema);
      expect(viaBase.payload[parentField], 'p2');
    });

    test('reparent does not disturb other units (geometry survives unchanged)',
        () {
      // Stand-in for "drag survives a reparent in flight". We use a custom
      // schema with a geometry unit to prove the parent write is isolated.
      final schema = withContainerUnits(const NodeSchema(
        type: 'Box',
        mergeUnits: {
          'geometry': ['left', 'top'],
        },
      ));
      final dragged = GraphNode(
        id: 'c',
        type: 'Box',
        payload: {'left': 50.0, 'top': 80.0, parentField: 'p0'},
        stamps: {
          'geometry': _stamp('alice', 3),
          parentUnit: _stamp('seed', 0),
        },
      );
      final reparented = GraphNode(
        id: 'c',
        type: 'Box',
        payload: {parentField: 'p9'},
        stamps: {parentUnit: _stamp('bob', 2)},
      );
      final merged = mergeNodes(dragged, reparented, schema);
      expect(merged.payload['left'], 50.0);
      expect(merged.payload['top'], 80.0);
      expect(merged.payload[parentField], 'p9');
    });
  });

  group('fractional_index.between', () {
    test('null/null seeds around firstIndex (with random tiebreaker)', () {
      // Post-fix (cage-match P1): first-insert now appends a 4-char random
      // suffix so two concurrent empty-container inserts can't collide on the
      // bare 'O' and then crash a follow-up between('O','O').
      final k = between(null, null);
      expect(k.startsWith(firstIndex), isTrue, reason: 'seed prefix preserved');
      expect(k.length, greaterThan(firstIndex.length),
          reason: 'tiebreaker appended');
    });

    test('null/null: concurrent first-inserts produce distinct keys', () {
      final keys = <String>{};
      for (var i = 0; i < 200; i++) {
        expect(keys.add(between(null, null)), isTrue,
            reason: 'first-insert collision');
      }
    });

    test('null/null: between(a, b) on two first-insert outputs works', () {
      // Two replicas independently called between(null, null); now a user
      // drops a third sibling between them. Pre-fix this threw because both
      // bare 'O' collided. Post-fix the two keys differ (random suffix), so
      // there is room for a midpoint.
      final a = between(null, null);
      final b = between(null, null);
      final lo = a.compareTo(b) < 0 ? a : b;
      final hi = a.compareTo(b) < 0 ? b : a;
      final mid = between(lo, hi);
      expect(lo.compareTo(mid) < 0, isTrue, reason: '$lo < $mid');
      expect(mid.compareTo(hi) < 0, isTrue, reason: '$mid < $hi');
    });

    test('monotone: before < between(before, after) < after', () {
      for (var i = 0; i < 50; i++) {
        final mid = between('A', 'Z');
        expect('A'.compareTo(mid) < 0, isTrue, reason: 'A < $mid');
        expect(mid.compareTo('Z') < 0, isTrue, reason: '$mid < Z');
      }
    });

    test('open-left: between(null, x) sorts before x', () {
      for (var i = 0; i < 20; i++) {
        final s = between(null, 'M');
        expect(s.compareTo('M') < 0, isTrue);
      }
    });

    test('open-right: between(x, null) sorts after x', () {
      for (var i = 0; i < 20; i++) {
        final s = between('M', null);
        expect('M'.compareTo(s) < 0, isTrue);
      }
    });

    test('terminating: narrow gaps still produce a strictly-between key', () {
      // Adjacent printable characters → midpoint must extend the string.
      final mid = between('A', 'B');
      expect('A'.compareTo(mid) < 0, isTrue);
      expect(mid.compareTo('B') < 0, isTrue);
    });

    test(
        'concurrent inserts at same gap produce distinct keys (random suffix)',
        () {
      // 200 concurrent "insert between A and Z" calls should all land distinct
      // with overwhelming probability — collisions would mean siblings
      // collapse onto one slot.
      final keys = <String>{};
      for (var i = 0; i < 200; i++) {
        final k = between('A', 'Z');
        expect(keys.add(k), isTrue, reason: 'collision on $k');
      }
    });

    test('rejects inverted bounds', () {
      expect(() => between('Z', 'A'), throwsArgumentError);
      expect(() => between('A', 'A'), throwsArgumentError);
    });

    test('isMonotonic helper agrees with sort', () {
      final keys = List.generate(20, (_) => between('A', 'Z'))..sort();
      expect(isMonotonic(keys), isTrue);
    });

    test('rejects bounds containing space (alphabet violation)', () {
      // cage-match HIGH (Carnot): space (0x20) is not a legal digit in our
      // alphabet, so seeing it in a bound means upstream corruption — better
      // to scream than to silently emit a key that violates ordering.
      expect(() => between('A ', 'B'), throwsArgumentError);
      expect(() => between('A', 'B '), throwsArgumentError);
      expect(() => between('A ', null), throwsArgumentError);
      expect(() => between(null, ' A'), throwsArgumentError);
    });

    test('between(A, B): wide gap produces a strictly-between key', () {
      final k = between('A', 'B');
      expect('A'.compareTo(k) < 0, isTrue, reason: 'A < $k');
      expect(k.compareTo('B') < 0, isTrue, reason: '$k < B');
    });

    test('between(A, A!): unsatisfiable gap throws (no silent miscompute)', () {
      // cage-match HIGH (Carnot): 'A!' is the literal smallest extension of
      // 'A' in [!..~], so the open interval (A, A!) contains no string.
      // Pre-fix, `_midpoint` emitted something like 'A!P…' that sorted
      // GREATER than 'A!' — silent contract violation. Post-fix we detect
      // and throw rather than mis-stamp a sibling.
      expect(() => between('A', 'A!'), throwsArgumentError);
    });

    test('all emitted keys live in the [!..~] alphabet (no space leakage)', () {
      bool allValid(String s) {
        for (var i = 0; i < s.length; i++) {
          final c = s.codeUnitAt(i);
          if (c < 0x21 || c > 0x7e) return false;
        }
        return true;
      }

      for (var i = 0; i < 100; i++) {
        expect(allValid(between(null, null)), isTrue);
        expect(allValid(between('A', 'Z')), isTrue);
        expect(allValid(between(null, 'M')), isTrue);
        expect(allValid(between('M', null)), isTrue);
      }
    });

    test('origin tail: cross-origin keys are mathematically distinct', () {
      // cage-match polish (Kelvin #3): threading origin makes
      // collision-freedom guaranteed across origins, not probabilistic.
      // Force identical RNG outcomes by drawing many keys with two distinct
      // origins — the origin tails differ at every key.
      final aliceKeys = List.generate(100, (_) => between('A', 'Z', origin: 'alice'));
      final bobKeys = List.generate(100, (_) => between('A', 'Z', origin: 'bob'));
      // No alice key equals any bob key.
      final aliceSet = aliceKeys.toSet();
      for (final k in bobKeys) {
        expect(aliceSet.contains(k), isFalse, reason: 'collision: $k');
      }
      // And the origin tail shows up as the literal trailing chars.
      for (final k in aliceKeys) {
        expect(k.endsWith('alic'), isTrue, reason: '$k missing alice tail');
      }
      for (final k in bobKeys) {
        expect(k.endsWith('bob_'), isTrue,
            reason: '$k missing bob tail (padded)');
      }
    });
  });

  group('hierarchy — children / descendants / ancestors', () {
    test('children sorted by zIndex, tombstoned filtered out', () {
      final p = _node('p', containerType: 'group');
      final a = _node('a', parent: 'p', zIndex: 'M');
      final b = _node('b', parent: 'p', zIndex: 'A');
      final c = _node('c', parent: 'p', zIndex: 'Z');
      final dead = _node('d', parent: 'p', zIndex: 'B', deleted: true);
      final outsider = _node('x', parent: 'other');

      final kids = children(p, [a, b, c, dead, outsider, p]).toList();
      expect(kids.map((n) => n.id).toList(), ['b', 'a', 'c']);
    });

    test('descendants walks transitively in z-order', () {
      final root = _node('r', containerType: 'frame');
      final g1 = _node('g1', parent: 'r', containerType: 'group', zIndex: 'A');
      final g2 = _node('g2', parent: 'r', containerType: 'group', zIndex: 'Z');
      final l1 = _node('l1', parent: 'g1', zIndex: 'M');
      final l2 = _node('l2', parent: 'g2', zIndex: 'M');
      final all = [root, g2, l2, g1, l1];

      final ids = descendants(root, all).map((n) => n.id).toList();
      expect(ids, ['g1', 'l1', 'g2', 'l2']);
    });

    test('ancestors walks up via parent pointer', () {
      final p = _node('p');
      final g = _node('g', parent: 'p');
      final c = _node('c', parent: 'g');
      final byId = {for (final n in [p, g, c]) n.id: n};
      expect(ancestors(c, byId).map((n) => n.id).toList(), ['g', 'p']);
    });

    test('ancestors is cycle-safe (terminates on malformed input)', () {
      // a→b→a cycle.
      final a = _node('a', parent: 'b');
      final b = _node('b', parent: 'a');
      final byId = {'a': a, 'b': b};
      final walked = ancestors(a, byId).toList();
      // Should terminate, not OOM. Exact contents are an implementation
      // detail; we just demand termination + bounded length.
      expect(walked.length, lessThanOrEqualTo(byId.length));
    });
  });

  group('hierarchy — dangling children', () {
    test('child of deleted parent is treated as root in roots()', () {
      final ghost = _node('ghost', containerType: 'group', deleted: true);
      final orphan = _node('orphan', parent: 'ghost', zIndex: 'M');
      final normal = _node('n');
      final all = [ghost, orphan, normal];
      final rootIds = roots(all).map((n) => n.id).toSet();
      expect(rootIds, {'orphan', 'n'});
    });

    test('parentOf returns null for dangling pointer', () {
      final ghost = _node('ghost', deleted: true);
      final orphan = _node('orphan', parent: 'ghost');
      final byId = {for (final n in [ghost, orphan]) n.id: n};
      expect(parentOf(orphan, byId), isNull);
    });

    test('missing parent (not in byId) is also dangling', () {
      final orphan = _node('orphan', parent: 'never-existed');
      expect(parentOf(orphan, {'orphan': orphan}), isNull);
      expect(roots([orphan]).map((n) => n.id), ['orphan']);
    });

    test('parentId payload survives deletion — resurrection re-attaches', () {
      // The dangling decision is "dont rewrite parentId." Prove the field
      // survives a tombstone → un-tombstone cycle (no implicit clear).
      final group = _node('g', containerType: 'group',
          stamps: {NodeSchema.tombstoneUnit: _stamp('a', 1)});
      final groupDeleted = GraphNode(
        id: 'g',
        type: 'Box',
        payload: {...group.payload, NodeSchema.tombstoneField: true},
        stamps: {NodeSchema.tombstoneUnit: _stamp('a', 2)},
      );
      final groupResurrected = GraphNode(
        id: 'g',
        type: 'Box',
        payload: {...group.payload, NodeSchema.tombstoneField: false},
        stamps: {NodeSchema.tombstoneUnit: _stamp('b', 3)},
      );
      final merged =
          mergeNodes(groupDeleted, groupResurrected, _schema);
      expect(merged.isDeleted, isFalse);
      // The child's parentId hasn't moved — it still points at 'g'. So after
      // resurrection, hierarchy lookups re-attach automatically.
      final child = _node('c', parent: 'g');
      final byId = {merged.id: merged, child.id: child};
      expect(parentOf(child, byId)?.id, 'g');
    });
  });

  group('hierarchy — wouldCreateCycle', () {
    test('refuses self-parent', () {
      final n = _node('n');
      expect(wouldCreateCycle('n', 'n', {'n': n}), isTrue);
    });

    test('refuses making node its own ancestor', () {
      // p → c (c is child of p). Moving p under c would form a cycle.
      final p = _node('p');
      final c = _node('c', parent: 'p');
      final byId = {'p': p, 'c': c};
      expect(wouldCreateCycle('p', 'c', byId), isTrue);
    });

    test('refuses deeper would-be cycle', () {
      final p = _node('p');
      final g = _node('g', parent: 'p');
      final c = _node('c', parent: 'g');
      final byId = {'p': p, 'g': g, 'c': c};
      // Moving p under c (its grandchild) would form p→...→p.
      expect(wouldCreateCycle('p', 'c', byId), isTrue);
    });

    test('allows legitimate reparent', () {
      final a = _node('a');
      final b = _node('b');
      final c = _node('c', parent: 'a');
      final byId = {'a': a, 'b': b, 'c': c};
      expect(wouldCreateCycle('c', 'b', byId), isFalse);
    });

    test('moving under a missing parent is not a cycle (just dangling soon)',
        () {
      final c = _node('c');
      expect(wouldCreateCycle('c', 'ghost', {'c': c}), isFalse);
    });
  });

  group('smoke: group with two children, concurrent group-move + child-rename',
      () {
    // Stretch test from the brief: a group containing two child boxes; one
    // peer moves the group's geometry, another renames a child. The merge
    // converges cleanly — orthogonal merge units don't collide across nodes.
    test('group geometry write and child label write both survive', () {
      final schema = withContainerUnits(const NodeSchema(
        type: 'Box',
        mergeUnits: {
          'geometry': ['left', 'top', 'right', 'bottom'],
          'label': ['name'],
        },
      ));

      // Group node — has containerType, is itself moveable.
      final groupSeed = GraphNode(
        id: 'g',
        type: 'Box',
        payload: {
          'left': 0.0,
          'top': 0.0,
          'right': 100.0,
          'bottom': 100.0,
          'name': 'Group A',
          containerTypeField: 'group',
        },
        stamps: {
          'geometry': _stamp('seed', 0),
          'label': _stamp('seed', 0),
          containerTypeUnit: _stamp('seed', 0),
        },
      );
      final child1Seed = GraphNode(
        id: 'c1',
        type: 'Box',
        payload: {'name': 'C1', parentField: 'g', zIndexField: 'A'},
        stamps: {
          'label': _stamp('seed', 0),
          parentUnit: _stamp('seed', 0),
          zIndexUnit: _stamp('seed', 0),
        },
      );

      // Alice moves the group.
      final groupMoved = GraphNode(
        id: 'g',
        type: 'Box',
        payload: {
          'left': 500.0,
          'top': 500.0,
          'right': 600.0,
          'bottom': 600.0,
        },
        stamps: {'geometry': _stamp('alice', 1)},
      );
      // Bob renames child1 concurrently.
      final child1Renamed = GraphNode(
        id: 'c1',
        type: 'Box',
        payload: {'name': 'Renamed'},
        stamps: {'label': _stamp('bob', 1)},
      );

      final gMerged = mergeNodes(groupSeed, groupMoved, schema);
      final cMerged = mergeNodes(child1Seed, child1Renamed, schema);

      // Group moved; containerType + name preserved.
      expect(gMerged.payload['left'], 500.0);
      expect(gMerged.payload['name'], 'Group A');
      expect(gMerged.payload[containerTypeField], 'group');
      // Child renamed; parent pointer preserved.
      expect(cMerged.payload['name'], 'Renamed');
      expect(cMerged.payload[parentField], 'g');

      // Hierarchy still resolves.
      final byId = {gMerged.id: gMerged, cMerged.id: cMerged};
      expect(parentOf(cMerged, byId)?.id, 'g');
      expect(children(gMerged, byId.values).map((n) => n.id).toList(), ['c1']);
    });
  });

  group('hierarchy — cycles after concurrent reparent', () {
    // cage-match HIGH (Carnot): Alice moves a→b, Bob moves b→a; both
    // wouldCreateCycle preflights return false locally, but post-merge the
    // graph holds a cycle. Pre-fix `descendants` recurses forever; `roots`
    // returns neither cyclic node. Post-fix `descendants` terminates and
    // `roots` promotes the cycle to root.
    test('descendants terminates on a 2-cycle (no infinite recursion)', () {
      final a = _node('a', parent: 'b');
      final b = _node('b', parent: 'a');
      // Walk from a — should terminate after at most O(n) steps. We bound
      // with a timeout via taking the first 100 elements; the iterator
      // should complete on its own well before.
      final walked = descendants(a, [a, b]).take(100).toList();
      expect(walked.length, lessThanOrEqualTo(2),
          reason: 'cycle walk should not yield duplicates');
    });

    test('descendants terminates on a 3-cycle with off-cycle children', () {
      // a→b→c→a cycle, plus leaf d→a (not in cycle).
      final a = _node('a', parent: 'c');
      final b = _node('b', parent: 'a');
      final c = _node('c', parent: 'b');
      final d = _node('d', parent: 'a');
      final walked = descendants(a, [a, b, c, d]).take(100).toList();
      // Must not include 'a' itself; must terminate.
      expect(walked.contains(a), isFalse);
      expect(walked.length, lessThanOrEqualTo(4));
    });

    test('roots promotes cyclic nodes (Alice a→b / Bob b→a scenario)', () {
      final a = _node('a', parent: 'b');
      final b = _node('b', parent: 'a');
      final c = _node('c'); // legit root
      final rootIds = roots([a, b, c]).map((n) => n.id).toSet();
      expect(rootIds, {'a', 'b', 'c'},
          reason: 'cyclic pair both promoted to root so renderer has something to draw');
    });

    test('inCycle detects loop membership', () {
      final a = _node('a', parent: 'b');
      final b = _node('b', parent: 'a');
      final c = _node('c'); // not in any cycle
      final d = _node('d', parent: 'a'); // dangling-into-cycle, not itself in
      final byId = {'a': a, 'b': b, 'c': c, 'd': d};
      expect(inCycle(a, byId), isTrue);
      expect(inCycle(b, byId), isTrue);
      expect(inCycle(c, byId), isFalse);
      expect(inCycle(d, byId), isFalse,
          reason: 'd points into a cycle but is not part of it');
    });
  });

  group('hierarchy — tombstoned-parent contract', () {
    // cage-match MEDIUM (Carnot): roots() promotes child-of-deleted to root,
    // but children(deletedParent, all) used to still return the child. The
    // two helpers disagreed about who owns the orphan. Post-fix:
    // children(deletedParent, …) is empty. roots() owns them.
    test('children(deletedParent, all) returns empty', () {
      final ghost = _node('ghost', containerType: 'group', deleted: true);
      final orphan = _node('orphan', parent: 'ghost');
      expect(children(ghost, [ghost, orphan]).toList(), isEmpty);
    });

    test('orphan still surfaces via roots() — consistent ownership', () {
      final ghost = _node('ghost', deleted: true);
      final orphan = _node('orphan', parent: 'ghost');
      final rootIds = roots([ghost, orphan]).map((n) => n.id).toSet();
      expect(rootIds, {'orphan'});
    });
  });

  group('classBoxSchema — container units are wired in', () {
    // cage-match P0 (Kelvin): `withContainerUnits` was defined but never
    // applied to `classBoxSchema`. That meant a real ClassBox-shaped node
    // with parent/containerType/zIndex stamps would have its container-unit
    // payload silently dropped on merge. Post-fix the schema is layered, so
    // the real production schema converges through `mergeNodes` correctly.
    test('classBoxSchema includes parent, containerType, zIndex units', () {
      // Imported at test top: classBoxSchema lives in class_box_schema.dart.
      expect(_classBoxUnits(), containsAll([
        parentUnit,
        containerTypeUnit,
        zIndexUnit,
        // Plus the original app units.
        'geometry', 'label',
      ]));
    });

    test(
        'real classBoxSchema honours parentId/zIndex stamps under mergeNodes',
        () {
      // Construct a ClassBox-shaped GraphNode with container stamps and
      // merge a reparent + reorder via the REAL classBoxSchema (not a
      // synthetic test schema). Pre-fix this dropped the container payload.
      final base = GraphNode(
        id: 'box1',
        type: 'ClassBox',
        payload: {
          'left': 0.0, 'top': 0.0, 'right': 100.0, 'bottom': 100.0,
          'name': 'Box',
          parentField: 'p0',
          zIndexField: 'M',
        },
        stamps: {
          'geometry': _stamp('seed', 0),
          'label': _stamp('seed', 0),
          parentUnit: _stamp('seed', 0),
          zIndexUnit: _stamp('seed', 0),
        },
      );
      final reparented = GraphNode(
        id: 'box1',
        type: 'ClassBox',
        payload: {parentField: 'p9', zIndexField: 'Z'},
        stamps: {
          parentUnit: _stamp('alice', 1),
          zIndexUnit: _stamp('alice', 1),
        },
      );

      final merged = mergeNodes(base, reparented, _realClassBoxSchema());

      expect(merged.payload[parentField], 'p9',
          reason: 'parent payload must follow the winning stamp');
      expect(merged.payload[zIndexField], 'Z');
      // Untouched units survive.
      expect(merged.payload['left'], 0.0);
      expect(merged.payload['name'], 'Box');
    });
  });
}

Iterable<String> _classBoxUnits() => cbs.classBoxSchema.mergeUnits.keys;
NodeSchema _realClassBoxSchema() => cbs.classBoxSchema;
