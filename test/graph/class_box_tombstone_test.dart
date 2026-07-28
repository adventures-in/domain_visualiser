import 'package:domain_visualiser/graph/class_box_schema.dart';
import 'package:domain_visualiser/graph/graph_envelope.dart';
import 'package:domain_visualiser/graph/hlc_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// The "clear" control tombstones every visible box via [classBoxTombstone].
/// These tests pin the CRDT semantics that make that safe: a delete is just a
/// stamp on the reserved tombstone unit, so it merges (not clobbers) against
/// the on-wire doc under the production [classBoxSchema].
void main() {
  /// A live box with distinct geometry + label units, authored by 'alice'
  /// before any tombstone exists.
  GraphNode liveBox() => GraphNode(
        id: 'box-1',
        type: 'ClassBox',
        payload: {
          'left': 1.0,
          'top': 2.0,
          'right': 3.0,
          'bottom': 4.0,
          'name': 'Order',
        },
        stamps: {
          'geometry': FieldStamp(
              hlc: '2026-05-27T08:00:00.000Z-0001-alice', origin: 'alice'),
          'label': FieldStamp(
              hlc: '2026-05-27T08:00:00.000Z-0001-alice', origin: 'alice'),
        },
      );

  group('classBoxTombstone', () {
    test('stamps only the reserved tombstone unit', () {
      final tomb = classBoxTombstone('box-1',
          hlc: HlcManager(nodeId: 'agent'), origin: 'agent');

      expect(tomb.id, 'box-1');
      expect(tomb.type, 'ClassBox');
      expect(tomb.stamps.keys, [NodeSchema.tombstoneUnit]);
      expect(tomb.payload, {NodeSchema.tombstoneField: true});
    });

    test('merging a tombstone over a live box marks it deleted', () {
      final tomb = classBoxTombstone('box-1',
          hlc: HlcManager(nodeId: 'agent'), origin: 'agent');

      final merged = mergeNodes(liveBox(), tomb, classBoxSchema);

      expect(merged.isDeleted, isTrue, reason: 'the tombstone unit wins');
    });

    test('deleting preserves the other units (name/geometry untouched)', () {
      final tomb = classBoxTombstone('box-1',
          hlc: HlcManager(nodeId: 'agent'), origin: 'agent');

      final merged = mergeNodes(liveBox(), tomb, classBoxSchema);

      // The tombstone carries no geometry/label fields, so the merge leaves
      // them exactly as authored — a delete is reversible, not a wipe.
      expect(merged.payload['name'], 'Order');
      expect(merged.payload['left'], 1.0);
    });

    test('delete is order-independent (commutative)', () {
      final tomb = classBoxTombstone('box-1',
          hlc: HlcManager(nodeId: 'agent'), origin: 'agent');

      final ab = mergeNodes(liveBox(), tomb, classBoxSchema);
      final ba = mergeNodes(tomb, liveBox(), classBoxSchema);

      expect(ab.isDeleted, ba.isDeleted);
      expect(ab.payload['name'], ba.payload['name']);
    });
  });
}
