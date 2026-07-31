import 'package:codraw/sync/sync_section.dart';
import 'package:codraw/graph/agent_draw_envelope.dart';
import 'package:codraw/graph/class_box_schema.dart';
import 'package:codraw/graph/graph_envelope.dart';
import 'package:codraw/graph/hlc_manager.dart';
import 'package:codraw/sync/firestore_backend.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards against the reserved-field-name class of bug: Firestore rejects any
/// field name (or nested map key) matching `__.*__` with a 400. Every existing
/// sync test passes against `fake_cloud_firestore`, which does NOT enforce that
/// rule — so the CRDT envelope shipped four reserved names that could never
/// persist to a real backend. This test re-imposes the rule at the unit level
/// so the fake can't hide a regression.
void main() {
  // Firestore's reserved-field pattern: leading AND trailing double underscore.
  final reserved = RegExp(r'^__.*__$');

  /// Recursively collects every field name / map key that a nested doc would
  /// present to Firestore.
  Iterable<String> allKeys(Object? value) sync* {
    if (value is Map) {
      for (final entry in value.entries) {
        yield entry.key.toString();
        yield* allKeys(entry.value);
      }
    } else if (value is List) {
      for (final e in value) {
        yield* allKeys(e);
      }
    }
  }

  void assertNoReserved(Iterable<String> keys, String context) {
    for (final k in keys) {
      expect(reserved.hasMatch(k), isFalse,
          reason: '$context: "$k" matches the reserved `__.*__` pattern and '
              'will be rejected by real Firestore');
    }
  }

  group('no wire identifier is a reserved Firestore field name', () {
    test('exported envelope constants are legal', () {
      assertNoReserved([
        envelopeKey,
        NodeSchema.tombstoneUnit,
        NodeSchema.tombstoneField,
        NodeSchema.legacyRowUnit,
      ], 'envelope constant');
    });

    test('ClassBox schema merge-unit names and payload fields are legal', () {
      assertNoReserved(classBoxSchema.mergeUnits.keys, 'merge-unit name');
      assertNoReserved(
          classBoxSchema.mergeUnits.values.expand((f) => f), 'payload field');
    });

    test('a fully-serialized envelope document has no reserved keys', () {
      final doc = agentClassBoxDoc(
        hlc: HlcManager(nodeId: 'a'),
        origin: 'a',
        left: 0.0,
        top: 0.0,
        right: 1.0,
        bottom: 1.0,
        name: 'X',
        instanceMethods: const ['m()'],
        userId: 'a',
      );
      // Include the tombstone in the check — it's the sneakiest reserved name.
      final withTomb = <String, Object?>{
        ...doc,
        NodeSchema.tombstoneField: false,
        envelopeKey: {
          'stamps': {
            ...((doc[envelopeKey] as Map)['stamps'] as Map),
            NodeSchema.tombstoneUnit: {'hlc': 'h', 'origin': 'a'},
          }
        },
      };
      assertNoReserved(allKeys(withTomb), 'serialized envelope');
    });

    test('the legacy-row re-serialization path emits no reserved keys',
        () async {
      // A doc written WITHOUT an envelope (legacy / non-domvis producer) is read
      // back by FirestoreBackend, which fabricates a row-grain stamp under a
      // reserved unit name. Exercise that path end-to-end and assert the doc it
      // writes back carries only legal keys.
      final shared = FakeFirebaseFirestore();
      final path =
          '${FirestoreBackend.locationOf[SyncSection.classBoxes]}/box-legacy';
      await shared.doc(path).set({
        'left': 0.0,
        'top': 0.0,
        'right': 10.0,
        'bottom': 10.0,
        'name': 'Legacy',
      });

      final backend = FirestoreBackend(
        database: shared,
        hlc: HlcManager(nodeId: 'reader'),
        origin: 'reader',
      );
      // A local update forces read-merge-write: the fabricated legacy stamp is
      // carried into the re-serialized doc's envelope.
      await backend.updateGraphNode(GraphNode(
        id: 'box-legacy',
        type: 'ClassBox',
        payload: {'name': 'Legacy2'},
        stamps: {'label': FieldStamp(hlc: 'h', origin: 'reader')},
      ));

      final landed = (await shared.doc(path).get()).data()!;
      assertNoReserved(allKeys(landed), 'legacy re-serialized doc');
    });
  });
}
