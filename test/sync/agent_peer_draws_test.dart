import 'dart:async';

import 'package:codraw/actions/domain-objects/store_class_boxes_action.dart';
import 'package:codraw/actions/redux_action.dart';
import 'package:codraw/sync/sync_section.dart';
import 'package:codraw/graph/agent_draw_envelope.dart';
import 'package:codraw/graph/class_box_schema.dart';
import 'package:codraw/graph/graph_envelope.dart';
import 'package:codraw/graph/hlc_manager.dart';
import 'package:codraw/sync/firestore_backend.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Acceptance test for ADR-0002 (agent-as-peer): an AI agent is just an
/// `origin + HLC`, so a `ClassBox` it authors into the shared transport must
/// appear on a human client's canvas via the exact same merge path a human
/// edit takes. "Drawing a diagram" == writing stamped envelopes the canvas
/// then projects.
///
/// The agent's wire bytes come from the single producer [agentClassBoxDoc];
/// the consumer under test is the real [FirestoreBackend], so a pass proves
/// the bytes are consumable, not merely self-consistent.
void main() {
  const agentOrigin = 'agent-claude';
  final path =
      '${FirestoreBackend.locationOf[SyncSection.classBoxes]}';

  group('agent-as-peer draws a ClassBox', () {
    test('an agent-authored envelope projects onto a human canvas', () async {
      final shared = FakeFirebaseFirestore();

      // The agent writes a box straight into the shared store.
      final agentHlc = HlcManager(nodeId: agentOrigin);
      final doc = agentClassBoxDoc(
        hlc: agentHlc,
        origin: agentOrigin,
        left: 60.0,
        top: 60.0,
        right: 260.0,
        bottom: 180.0,
        name: 'Order',
        instanceMethods: ['total()', 'addLine(item)'],
        userId: agentOrigin,
      );
      await shared.doc('$path/box-agent-order').set(doc);

      // A human client backend (distinct origin) connects and must project
      // the agent's box into the store on its first snapshot. Await the actual
      // projection event (system clock) rather than a fixed wall-time sleep, so
      // the test can't flake on a loaded CI box.
      final controller = StreamController<ReduxAction>();
      final projected = Completer<StoreClassBoxesAction>();
      final sub = controller.stream
          .where((a) => a is StoreClassBoxesAction)
          .cast<StoreClassBoxesAction>()
          .listen((a) {
        if (!projected.isCompleted &&
            a.boxes.any((b) => b.id == 'box-agent-order')) {
          projected.complete(a);
        }
      });
      final human = FirestoreBackend(
        database: shared,
        eventsController: controller,
        hlc: HlcManager(nodeId: 'human-1'),
        origin: 'human-1',
      );
      human.connect(SyncSection.classBoxes);

      final action =
          await projected.future.timeout(const Duration(seconds: 5));
      final box = action.boxes.singleWhere((b) => b.id == 'box-agent-order');
      expect(box.name, 'Order');
      expect(box.left, 60.0);
      expect(box.top, 60.0);
      expect(box.right, 260.0);
      expect(box.bottom, 180.0);
      expect(box.instanceMethods, contains('total()'));

      await sub.cancel();
      human.disconnect(SyncSection.classBoxes);
    });

    test('a human rename converges with the agent draw, conflict-free',
        () async {
      final shared = FakeFirebaseFirestore();

      // 1. Agent draws the box.
      final agentHlc = HlcManager(nodeId: agentOrigin);
      await shared.doc('$path/box-shared').set(agentClassBoxDoc(
            hlc: agentHlc,
            origin: agentOrigin,
            left: 0.0,
            top: 0.0,
            right: 100.0,
            bottom: 60.0,
            name: 'Ordr', // agent's typo, about to be fixed by a human
          ));

      // 2. A human, on their own backend, renames it (label unit only). The
      //    read-merge-write transaction must keep the agent's geometry.
      final humanHlc = HlcManager(nodeId: 'human-1');
      // Observe the agent's stamps so the human's HLC sorts strictly after.
      final onWire = (await shared.doc('$path/box-shared').get()).data()!;
      final wireStamps =
          (onWire[envelopeKey] as Map)['stamps'] as Map;
      for (final s in wireStamps.values) {
        humanHlc.observe((s as Map)['hlc'] as String);
      }
      final human = FirestoreBackend(
        database: shared,
        hlc: humanHlc,
        origin: 'human-1',
      );
      await human.updateGraphNode(GraphNode(
        id: 'box-shared',
        type: 'ClassBox',
        payload: {'name': 'Order'},
        stamps: {'label': FieldStamp(hlc: humanHlc.issue(), origin: 'human-1')},
      ));

      // 3. The durable doc carries the human's label AND the agent's geometry,
      //    each stamped by its own origin — provenance survives the merge.
      final landed = (await shared.doc('$path/box-shared').get()).data()!;
      expect(landed['name'], 'Order', reason: 'human rename won its unit');
      expect(landed['right'], 100.0, reason: 'agent geometry survived');
      final stamps = (landed[envelopeKey] as Map)['stamps'] as Map;
      expect((stamps['label'] as Map)['origin'], 'human-1');
      expect((stamps['geometry'] as Map)['origin'], agentOrigin);
    });

    test('producer stays in lock-step with the real ClassBox schema', () {
      // Drift guard: the producer stamps a subset of the real schema's units.
      // This test — which loads the real schema — fails if the producer ever
      // stamps a unit the canvas doesn't declare. (The envelope KEY can no
      // longer drift: agent_draw_envelope imports envelopeKey directly.)
      final doc = agentClassBoxDoc(
        hlc: HlcManager(nodeId: agentOrigin),
        origin: agentOrigin,
        left: 0.0,
        top: 0.0,
        right: 1.0,
        bottom: 1.0,
        name: 'X',
        instanceMethods: const ['m()'],
      );
      final units =
          ((doc[envelopeKey] as Map)['stamps'] as Map).keys.cast<String>();
      final legal = {...classBoxSchema.mergeUnits.keys};
      for (final unit in units) {
        expect(legal.contains(unit), isTrue,
            reason: 'unit "$unit" is not declared in classBoxSchema');
      }
    });
  });
}
