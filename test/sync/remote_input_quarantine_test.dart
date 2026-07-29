import 'dart:async';

import 'package:domain_visualiser/actions/domain-objects/store_class_boxes_action.dart';
import 'package:domain_visualiser/actions/problems/add_problem_action.dart';
import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/graph/agent_draw_envelope.dart';
import 'package:domain_visualiser/graph/class_box_schema.dart' show envelopeKey;
import 'package:domain_visualiser/graph/graph_envelope.dart';
import 'package:domain_visualiser/graph/hlc_manager.dart';
import 'package:domain_visualiser/sync/firestore_backend.dart';
import 'package:domain_visualiser/sync/sync_section.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// The remote-input trust boundary: agent-as-peer means accepting writes from
/// producers we do not control, so ONE malformed/hostile doc must be quarantined
/// (skipped + logged) — never allowed to throw inside _absorbRemoteSnapshot and
/// route EVERY user's canvas to ProblemPage. This is the severity-driving face
/// of the seam-hardening task.
void main() {
  final path = FirestoreBackend.locationOf[SyncSection.classBoxes]!;

  test('one malformed remote doc is quarantined — the canvas survives',
      () async {
    final shared = FakeFirebaseFirestore();

    // A good box from a real producer.
    await shared.doc('$path/good').set(agentClassBoxDoc(
          hlc: HlcManager(nodeId: 'author'),
          origin: 'author',
          left: 0.0,
          top: 0.0,
          right: 100.0,
          bottom: 60.0,
          name: 'Good',
        ));

    // A POISON doc: an envelope whose stamp is missing `origin` — exactly the
    // shape that used to throw inside _absorbRemoteSnapshot (FieldStamp.fromJson
    // casts `origin as String` on null) and DoS the whole canvas.
    await shared.doc('$path/poison').set({
      'name': 'Poison',
      'left': 0.0,
      'top': 0.0,
      'right': 10.0,
      'bottom': 10.0,
      envelopeKey: {
        'stamps': {
          'geometry': {'hlc': '2026-05-27T08:00:00.000Z-0001-x'} // no origin
        }
      },
    });

    final controller = StreamController<ReduxAction>.broadcast();
    var problems = 0;
    final probSub =
        controller.stream.where((a) => a is AddProblemAction).listen((_) => problems++);

    final backend = FirestoreBackend(
      database: shared,
      eventsController: controller,
      hlc: HlcManager(nodeId: 'me'),
      origin: 'me',
    );

    final projected = controller.stream
        .where((a) => a is StoreClassBoxesAction)
        .cast<StoreClassBoxesAction>()
        .firstWhere((a) => a.boxes.any((b) => b.id == 'good'))
        .timeout(const Duration(seconds: 5));
    backend.connect(SyncSection.classBoxes);

    final action = await projected;
    // The good box renders...
    expect(action.boxes.any((b) => b.id == 'good'), isTrue);
    // ...the poison one is skipped, not rendered...
    expect(action.boxes.any((b) => b.id == 'poison'), isFalse);
    // ...and NOTHING routed the app to ProblemPage.
    await Future<void>.delayed(Duration.zero);
    expect(problems, 0,
        reason: 'a malformed remote doc must not DoS the canvas via addProblem');

    await probSub.cancel();
    backend.disconnect(SyncSection.classBoxes);
  });

  // The trust boundary has TWO read doors, not one: the absorb path (above) AND
  // the _writeMerged transaction, which reads the current on-wire doc when a
  // local edit lands. A poison doc at an id a user later edits must NOT throw
  // inside the transaction → addProblem → whole-canvas DoS. Cage-match PR #13
  // (Carnot + Tesla) confirmed this second door was unguarded.
  test('write path: a local edit over a poison remote doc does not DoS — and self-heals',
      () async {
    final shared = FakeFirebaseFirestore();

    // A poison doc already sits at id 'shared' (a foreign/partial writer).
    await shared.doc('$path/shared').set({
      'left': 0.0,
      'top': 0.0,
      'right': 10.0,
      'bottom': 10.0,
      envelopeKey: {
        'stamps': {
          'geometry': {'hlc': '2026-05-27T08:00:00.000Z-0001-x'} // no origin
        }
      },
    });

    final controller = StreamController<ReduxAction>.broadcast();
    var problems = 0;
    final probSub = controller.stream
        .where((a) => a is AddProblemAction)
        .listen((_) => problems++);

    final backend = FirestoreBackend(
      database: shared,
      eventsController: controller,
      hlc: HlcManager(nodeId: 'me'),
      origin: 'me',
    );

    // A local write to the SAME id. Pre-fix this threw inside runTransaction
    // (bare _readGraphNodeFromDoc on the poison base) → addProblem.
    final local = GraphNode(
      id: 'shared',
      type: 'ClassBox',
      payload: const {
        'left': 5.0,
        'top': 5.0,
        'right': 55.0,
        'bottom': 45.0,
        'name': 'Local',
      },
      stamps: {'geometry': FieldStamp(hlc: '2026-05-27T09:00:00.000Z-0001-me', origin: 'me')},
    );
    await backend.addGraphNode(local);

    await Future<void>.delayed(Duration.zero);
    expect(problems, 0,
        reason: 'a poison base in the write transaction must not DoS the canvas');

    // Self-heal: our validated write replaced the poison on the wire, so the
    // on-wire doc is now re-readable (quarantined base treated as "no base").
    final healed = await shared.doc('$path/shared').get();
    final env = (healed.data()![envelopeKey] as Map)['stamps'] as Map;
    expect((env['geometry'] as Map)['origin'], 'me',
        reason: 'the poison doc should be overwritten by the valid local write');

    await probSub.cancel();
    backend.disconnect(SyncSection.classBoxes);
  });

  // Finding #4 (Tesla): a stamp-valid doc whose payload has a wrong-typed field
  // parses and validates, but graphNodeToClassBox's `as num?` cast throws at
  // projection — OUTSIDE the per-doc guard — unless the door dry-runs projection.
  test('unprojectable payload (wrong-typed field) is quarantined at the door',
      () async {
    final shared = FakeFirebaseFirestore();
    await shared.doc('$path/good').set(agentClassBoxDoc(
          hlc: HlcManager(nodeId: 'author'),
          origin: 'author',
          left: 0.0,
          top: 0.0,
          right: 100.0,
          bottom: 60.0,
          name: 'Good',
        ));
    // `left` is a String — valid stamps, but `left as num?` throws at projection.
    await shared.doc('$path/unprojectable').set({
      'left': 'banana',
      'top': 0.0,
      'right': 10.0,
      'bottom': 10.0,
      envelopeKey: {
        'stamps': {
          'geometry': {
            'hlc': '2026-05-27T08:00:00.000Z-0001-x',
            'origin': 'author',
          }
        }
      },
    });

    final controller = StreamController<ReduxAction>.broadcast();
    var problems = 0;
    final probSub = controller.stream
        .where((a) => a is AddProblemAction)
        .listen((_) => problems++);
    final backend = FirestoreBackend(
      database: shared,
      eventsController: controller,
      hlc: HlcManager(nodeId: 'me'),
      origin: 'me',
    );
    final projected = controller.stream
        .where((a) => a is StoreClassBoxesAction)
        .cast<StoreClassBoxesAction>()
        .firstWhere((a) => a.boxes.any((b) => b.id == 'good'))
        .timeout(const Duration(seconds: 5));
    backend.connect(SyncSection.classBoxes);

    final action = await projected;
    expect(action.boxes.any((b) => b.id == 'good'), isTrue);
    expect(action.boxes.any((b) => b.id == 'unprojectable'), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(problems, 0,
        reason: 'an unprojectable payload must be quarantined, not DoS the canvas');

    await probSub.cancel();
    backend.disconnect(SyncSection.classBoxes);
  });

  // Finding #2 (Maxwell + Carnot): an enveloped doc with an empty `stamps` map
  // can neither order nor echo-suppress — corruption, not concurrency.
  test('an enveloped doc with no stamps is quarantined', () async {
    final shared = FakeFirebaseFirestore();
    await shared.doc('$path/good').set(agentClassBoxDoc(
          hlc: HlcManager(nodeId: 'author'),
          origin: 'author',
          left: 0.0,
          top: 0.0,
          right: 100.0,
          bottom: 60.0,
          name: 'Good',
        ));
    await shared.doc('$path/stampless').set({
      'left': 0.0,
      'top': 0.0,
      'right': 10.0,
      'bottom': 10.0,
      envelopeKey: {'stamps': <String, dynamic>{}},
    });

    final controller = StreamController<ReduxAction>.broadcast();
    var problems = 0;
    final probSub = controller.stream
        .where((a) => a is AddProblemAction)
        .listen((_) => problems++);
    final backend = FirestoreBackend(
      database: shared,
      eventsController: controller,
      hlc: HlcManager(nodeId: 'me'),
      origin: 'me',
    );
    final projected = controller.stream
        .where((a) => a is StoreClassBoxesAction)
        .cast<StoreClassBoxesAction>()
        .firstWhere((a) => a.boxes.any((b) => b.id == 'good'))
        .timeout(const Duration(seconds: 5));
    backend.connect(SyncSection.classBoxes);

    final action = await projected;
    expect(action.boxes.any((b) => b.id == 'stampless'), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(problems, 0);

    await probSub.cancel();
    backend.disconnect(SyncSection.classBoxes);
  });
}
