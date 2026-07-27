import 'package:domain_visualiser/graph/graph_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

/// domain_visualiser's ClassBox grain: geometry moves as one unit, label and
/// each list are independent units. This is the declaration the engine honours.
const _classBoxSchema = NodeSchema(
  type: 'ClassBox',
  mergeUnits: {
    'geometry': ['left', 'top', 'right', 'bottom'],
    'label': ['name'],
    'instanceMethods': ['instanceMethods'],
  },
);

/// Builds a stamp; later [seq] sorts lexicographically after earlier ones.
FieldStamp _stamp(String origin, int seq) =>
    FieldStamp(hlc: '2026-05-27T08:00:00.000Z-${seq.toString().padLeft(4, '0')}-$origin', origin: origin);

GraphNode _box({
  required Map<String, Object?> payload,
  required Map<String, FieldStamp> stamps,
}) =>
    GraphNode(id: 'box-1', type: 'ClassBox', payload: payload, stamps: stamps);

void main() {
  group('mergeNodes', () {
    test('concurrent drag + rename: both edits survive (no clobber)', () {
      // Common ancestor.
      final base = _box(
        payload: {'left': 0.0, 'top': 0.0, 'right': 10.0, 'bottom': 10.0, 'name': 'A'},
        stamps: {'geometry': _stamp('seed', 0), 'label': _stamp('seed', 0)},
      );
      // Alice drags (new geometry); Bob renames (new label). Independent units.
      final alice = _box(
        payload: {...base.payload, 'left': 100.0, 'right': 110.0},
        stamps: {...base.stamps, 'geometry': _stamp('alice', 1)},
      );
      final bob = _box(
        payload: {...base.payload, 'name': 'B'},
        stamps: {...base.stamps, 'label': _stamp('bob', 1)},
      );

      final merged = mergeNodes(alice, bob, _classBoxSchema);

      expect(merged.payload['left'], 100.0, reason: "Alice's drag survives");
      expect(merged.payload['name'], 'B', reason: "Bob's rename survives");
    });

    test('concurrent drag + drag: box never tears (geometry is one unit)', () {
      final alice = _box(
        payload: {'left': 1.0, 'top': 1.0, 'right': 2.0, 'bottom': 2.0},
        stamps: {'geometry': _stamp('alice', 1)},
      );
      final bob = _box(
        payload: {'left': 5.0, 'top': 5.0, 'right': 9.0, 'bottom': 9.0},
        stamps: {'geometry': _stamp('bob', 2)}, // higher HLC → Bob wins
      );

      final merged = mergeNodes(alice, bob, _classBoxSchema);

      // The winning side's geometry is taken WHOLE — no mix of Alice's left
      // with Bob's right.
      expect(merged.payload['left'], 5.0);
      expect(merged.payload['right'], 9.0);
      expect(merged.payload['top'], 5.0);
      expect(merged.payload['bottom'], 9.0);
    });

    test('merge is commutative — replicas converge regardless of order', () {
      final alice = _box(
        payload: {'name': 'from-alice'},
        stamps: {'label': _stamp('alice', 1)},
      );
      final bob = _box(
        payload: {'name': 'from-bob'},
        stamps: {'label': _stamp('bob', 2)},
      );

      final ab = mergeNodes(alice, bob, _classBoxSchema);
      final ba = mergeNodes(bob, alice, _classBoxSchema);

      expect(ab.payload['name'], ba.payload['name']);
      expect(ab.payload['name'], 'from-bob', reason: 'higher HLC wins both ways');
    });

    test('delete vs late edit: higher HLC wins through the same path', () {
      final deleted = _box(
        payload: {'name': 'X', NodeSchema.tombstoneField: true},
        stamps: {NodeSchema.tombstoneUnit: _stamp('alice', 1)},
      );
      final lateEdit = _box(
        payload: {'name': 'X-renamed', NodeSchema.tombstoneField: false},
        stamps: {
          NodeSchema.tombstoneUnit: _stamp('bob', 2)
        }, // resurrection wins (higher HLC)
      );

      final merged = mergeNodes(deleted, lateEdit, _classBoxSchema);
      expect(merged.isDeleted, isFalse, reason: 'later un-delete resurrects');
    });

    test('round-trips through JSON unchanged', () {
      final node = _box(
        payload: {'left': 1.0, 'name': 'A', NodeSchema.tombstoneField: false},
        stamps: {'geometry': _stamp('a', 1), 'label': _stamp('a', 1)},
      );
      final restored = GraphNode.fromJson(node.toJson());
      expect(restored.payload, node.payload);
      expect(restored.stamps['geometry']!.hlc, node.stamps['geometry']!.hlc);
    });

    test('partial-payload unit is commutative (winner omits a co-unit field)', () {
      // Symmetric to the edge suite: the fix lives in the shared _mergeUnits, so
      // the node path owns a regression that would catch a future split.
      final alice = _box(
        payload: {'left': 1.0, 'top': 1.0, 'right': 2.0, 'bottom': 2.0},
        stamps: {'geometry': _stamp('alice', 1)},
      );
      final bob = _box(
        payload: {'left': 5.0, 'top': 5.0, 'right': 9.0}, // omits bottom
        stamps: {'geometry': _stamp('bob', 2)}, // higher HLC wins
      );
      final ab = mergeNodes(alice, bob, _classBoxSchema);
      final ba = mergeNodes(bob, alice, _classBoxSchema);
      expect(ab.toJson(), ba.toJson());
      expect(ab.payload.containsKey('bottom'), isFalse,
          reason: 'winner omitted it → absent, not null');
    });

    test('wrong schema fails closed at runtime (schema.type != node.type)', () {
      final a = _box(payload: {'name': 'A'}, stamps: {'label': _stamp('a', 1)});
      final b = _box(payload: {'name': 'B'}, stamps: {'label': _stamp('b', 2)});
      const wrongSchema = NodeSchema(type: 'Frame', mergeUnits: {'label': ['name']});
      expect(() => mergeNodes(a, b, wrongSchema), throwsStateError);
    });

    test('divergent node id fails closed at runtime (StateError, not assert)', () {
      final a = _box(payload: {'name': 'A'}, stamps: {'label': _stamp('a', 1)});
      final b = GraphNode(
        id: 'box-2', // different id → distinct nodes, must not silently merge
        type: 'ClassBox',
        payload: {'name': 'B'},
        stamps: {'label': _stamp('b', 2)},
      );
      expect(() => mergeNodes(a, b, _classBoxSchema), throwsStateError);
    });

    test('divergent node type fails closed (identity is (id, type))', () {
      final a = _box(payload: {'name': 'A'}, stamps: {'label': _stamp('a', 1)});
      final b = GraphNode(
        id: 'box-1', // same id...
        type: 'Frame', // ...different type — identity divergence
        payload: {'name': 'B'},
        stamps: {'label': _stamp('b', 2)},
      );
      expect(() => mergeNodes(a, b, _classBoxSchema), throwsStateError);
    });
  });
}
