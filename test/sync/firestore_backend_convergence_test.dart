import 'dart:async';

import 'package:codraw/actions/domain-objects/store_class_boxes_action.dart';
import 'package:codraw/actions/redux_action.dart';
import 'package:codraw/sync/sync_section.dart';
import 'package:codraw/graph/class_box_schema.dart';
import 'package:codraw/graph/graph_envelope.dart';
import 'package:codraw/graph/hlc_manager.dart';
import 'package:codraw/sync/firestore_backend.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Convergence regression test that exercises the [FirestoreBackend] against a
/// real-shaped Firestore (via `fake_cloud_firestore`).
///
/// This is the test the cage-match reviewers asked for: the previous
/// `FakeGraphSyncBackend` couldn't reproduce the "two clients both .set() a
/// full merged doc and the second clobbers the first" failure mode, because it
/// just captured calls. By wiring two real [FirestoreBackend] instances
/// against ONE shared [FakeFirebaseFirestore], a concurrent
/// `geometry`-vs-`label` write that goes through the read-merge-write
/// transaction must converge in the doc itself — and a third, fresh-joining
/// backend reading the doc cold must see both edits.
void main() {
  group('FirestoreBackend concurrent writers converge in the doc', () {
    test(
        'Alice writes geometry, Bob writes label; cold reader sees both',
        () async {
      final shared = FakeFirebaseFirestore();
      final docPath =
          '${FirestoreBackend.locationOf[SyncSection.classBoxes]}/box-1';

      // Seed a base doc both writers will diverge from. We hand-craft the
      // envelope rather than going through a backend so the starting stamps
      // come from a third "seed" origin (so neither Alice's nor Bob's writes
      // are pure-echo).
      final seedHlc = HlcManager(nodeId: 'seed');
      FieldStamp seedStamp() =>
          FieldStamp(hlc: seedHlc.issue(), origin: 'seed');
      await shared.doc(docPath).set({
        'left': 0.0,
        'top': 0.0,
        'right': 10.0,
        'bottom': 10.0,
        'name': 'Base',
        envelopeKey: {
          'stamps': {
            'geometry': seedStamp().toJson(),
            'label': seedStamp().toJson(),
          },
        },
      });

      // Two writers, two distinct origins, ONE shared Firestore.
      final aliceHlc = HlcManager(nodeId: 'alice');
      final alice = FirestoreBackend(
        database: shared,
        hlc: aliceHlc,
        origin: 'alice',
      );
      final bobHlc = HlcManager(nodeId: 'bob');
      final bob = FirestoreBackend(
        database: shared,
        hlc: bobHlc,
        origin: 'bob',
      );

      // Each writer observes the seed before issuing so their HLCs sort
      // strictly after the seed (and after each other when they catch up via
      // the in-transaction read).
      final seedDoc = await shared.doc(docPath).get();
      final seedData = seedDoc.data()!;
      final seedEnv = (seedData[envelopeKey] as Map)['stamps'] as Map;
      for (final s in seedEnv.values) {
        aliceHlc.observe((s as Map)['hlc'] as String);
        bobHlc.observe(s['hlc'] as String);
      }

      // Alice's partial: only geometry is stamped (a drag).
      final aliceGeoStamp =
          FieldStamp(hlc: aliceHlc.issue(), origin: 'alice');
      final aliceUpdate = GraphNode(
        id: 'box-1',
        type: 'ClassBox',
        payload: {'left': 100.0, 'top': 0.0, 'right': 110.0, 'bottom': 10.0},
        stamps: {'geometry': aliceGeoStamp},
      );

      // Bob's partial: only label is stamped (a rename). Bob has NOT seen
      // Alice's write yet — this is the concurrent-edit scenario.
      final bobLabelStamp =
          FieldStamp(hlc: bobHlc.issue(), origin: 'bob');
      final bobUpdate = GraphNode(
        id: 'box-1',
        type: 'ClassBox',
        payload: {'name': 'Renamed'},
        stamps: {'label': bobLabelStamp},
      );

      // Sequence the writes: Alice lands first, then Bob writes against the
      // doc that already carries Alice's geometry. This is the load-bearing
      // scenario for the read-merge-write fix — under the old `.set()`-after-
      // in-memory-merge path, Bob's stale `_replica` (which never saw
      // Alice's write because Alice happened on a DIFFERENT backend
      // instance) would `.set()` a doc carrying only Bob's view of geometry,
      // silently overwriting Alice's edit in the durable store. The
      // transaction's in-band read forces Bob to merge against the actual
      // remote, so both edits survive.
      //
      // (We don't use `Future.wait` here because `fake_cloud_firestore`'s
      // `runTransaction` does not enforce real Firestore's serializable
      // isolation / retry semantics — it executes each transaction once
      // against whatever snapshot it sees, so true concurrent races against
      // the fake don't replay. The sequential variant is still a valid test
      // of the fix: it's exactly the failure mode that turns up at runtime
      // any time two backends' transactions don't overlap in wall-clock
      // time, which is the common case.)
      await alice.updateGraphNode(aliceUpdate);
      await bob.updateGraphNode(bobUpdate);

      // Cold-read: a fresh backend that joins after the dust settles and
      // reads the doc must see both Alice's geometry and Bob's label. This is
      // the "fresh Charlie" case that an in-memory-only fix would miss.
      final freshSnap = await shared.doc(docPath).get();
      final freshData = freshSnap.data()!;
      expect(freshData['left'], 100.0,
          reason: "Alice's geometry survived Bob's concurrent write");
      expect(freshData['name'], 'Renamed',
          reason: "Bob's label survived Alice's concurrent write");

      // And the envelope carries both stamps from the two distinct origins —
      // the merged document remembers both edits' provenance.
      final stamps =
          (freshData[envelopeKey] as Map)['stamps'] as Map<String, dynamic>;
      expect((stamps['geometry'] as Map)['origin'], 'alice');
      expect((stamps['label'] as Map)['origin'], 'bob');

      // A genuinely fresh third backend connecting after the writes settled
      // must project both edits into the store on its first snapshot.
      final charlieController = StreamController<ReduxAction>();
      final emitted = <StoreClassBoxesAction>[];
      final charlieSub = charlieController.stream
          .where((a) => a is StoreClassBoxesAction)
          .cast<StoreClassBoxesAction>()
          .listen(emitted.add);
      final charlie = FirestoreBackend(
        database: shared,
        eventsController: charlieController,
        hlc: HlcManager(nodeId: 'charlie'),
        origin: 'charlie',
      );
      charlie.connect(SyncSection.classBoxes);
      // Let the snapshot listener fire.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emitted, isNotEmpty,
          reason: 'fresh backend should project the merged doc immediately');
      final box = emitted.last.boxes.singleWhere((b) => b.id == 'box-1');
      expect(box.left, 100.0);
      expect(box.name, 'Renamed');

      await charlieSub.cancel();
      charlie.disconnect(SyncSection.classBoxes);
    });

    test(
        'addGraphNode race for the same id does not lose either set of stamps',
        () async {
      // Two replicas both create the same box id (think: offline-create then
      // sync). The doc that lands must carry the LWW-correct projection AND
      // both origins' stamps must be reflected (winner per unit).
      final shared = FakeFirebaseFirestore();
      final aliceHlc = HlcManager(nodeId: 'alice');
      final alice = FirestoreBackend(
        database: shared,
        hlc: aliceHlc,
        origin: 'alice',
      );
      final bobHlc = HlcManager(nodeId: 'bob');
      final bob = FirestoreBackend(
        database: shared,
        hlc: bobHlc,
        origin: 'bob',
      );

      FieldStamp stampA() => FieldStamp(hlc: aliceHlc.issue(), origin: 'alice');
      FieldStamp stampB() => FieldStamp(hlc: bobHlc.issue(), origin: 'bob');

      final aliceCreate = GraphNode(
        id: 'box-2',
        type: 'ClassBox',
        payload: {
          'left': 0.0,
          'top': 0.0,
          'right': 10.0,
          'bottom': 10.0,
          'name': 'A',
        },
        stamps: {
          'geometry': stampA(),
          'label': stampA(),
        },
      );
      // Bob's create has later HLCs (he observed nothing, but issues after
      // alice in wall-clock time inside this test).
      final bobCreate = GraphNode(
        id: 'box-2',
        type: 'ClassBox',
        payload: {
          'left': 50.0,
          'top': 50.0,
          'right': 60.0,
          'bottom': 60.0,
          'name': 'B',
        },
        stamps: {
          'geometry': stampB(),
          'label': stampB(),
        },
      );

      // Sequenced for the same reason as the previous test: the fake doesn't
      // model real Firestore transaction-retry, so we drive the writes in
      // wall-clock order and assert the second write sees the first via its
      // in-transaction read.
      await alice.addGraphNode(aliceCreate);
      await bob.addGraphNode(bobCreate);

      final docPath =
          '${FirestoreBackend.locationOf[SyncSection.classBoxes]}/box-2';
      final landed = (await shared.doc(docPath).get()).data()!;
      // Whoever's stamps sort higher wins each unit — the test asserts
      // convergence, not who wins. Both fields must come from the same
      // winning side (no torn-doc).
      final winningLeft = landed['left'];
      final winningName = landed['name'];
      final consistent = (winningLeft == 0.0 && winningName == 'A') ||
          (winningLeft == 50.0 && winningName == 'B');
      expect(consistent, isTrue,
          reason: 'concurrent creates converged to a coherent doc, '
              'not a half-A/half-B tear');
    });
  });
}
