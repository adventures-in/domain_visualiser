import 'dart:async';

import 'package:codraw/actions/domain-objects/store_class_boxes_action.dart';
import 'package:codraw/actions/problems/add_problem_action.dart';
import 'package:codraw/actions/redux_action.dart';
import 'package:codraw/graph/agent_draw_envelope.dart';
import 'package:codraw/graph/class_box_schema.dart' show envelopeKey, typeKey;
import 'package:codraw/graph/graph_envelope.dart';
import 'package:codraw/graph/hlc_manager.dart';
import 'package:codraw/sync/firestore_backend.dart';
import 'package:codraw/sync/sync_section.dart';
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

  // Slice 0 of the type-aware read path (#2432): the registry registers ClassBox
  // ALONE, so a doc declaring a present-but-UNREGISTERED `_type` (e.g. 'Person')
  // must be quarantined at the door — skipped + breadcrumb, never merged under the
  // wrong schema (silent field loss) and never a throw that DoS's the batch. This
  // is the new degenerate state the registry dispatch introduces; it must stay
  // sealed. NOTE the doc is otherwise WELL-FORMED (valid envelope, stamp, geometry)
  // so the ONLY reason it quarantines is the unregistered type.
  test('a present-but-unregistered _type is quarantined — the batch survives',
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

    // A perfectly-formed doc that merely declares an unregistered node type.
    await shared.doc('$path/person').set({
      typeKey: 'Person',
      'left': 10.0,
      'top': 10.0,
      'right': 90.0,
      'bottom': 90.0,
      'name': 'Ada',
      envelopeKey: {
        'stamps': {
          'geometry': {
            'hlc': '2026-05-27T08:00:00.000Z-0001-author',
            'origin': 'author'
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
    // The good ClassBox renders...
    expect(action.boxes.any((b) => b.id == 'good'), isTrue);
    // ...the unregistered-type doc is skipped, not rendered as a ClassBox...
    expect(action.boxes.any((b) => b.id == 'person'), isFalse);
    // ...and NOTHING routed the app to ProblemPage.
    await Future<void>.delayed(Duration.zero);
    expect(problems, 0,
        reason: 'an unregistered node type must quarantine, never DoS the canvas');

    await probSub.cancel();
    backend.disconnect(SyncSection.classBoxes);
  });

  // A PRESENT-but-malformed `_type` (explicit null, or a non-string) is NOT
  // absence — it must quarantine, never silently fall back to ClassBox (Carnot,
  // cage-match PR #20: `(data[_type] as String?) ?? 'ClassBox'` swallowed an
  // explicit null into the ClassBox fallback). Absence alone means ClassBox.
  for (final malformed in <Object?>[null, 7]) {
    test('a present-but-non-string _type ($malformed) is quarantined, not ClassBox',
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
      await shared.doc('$path/malformed').set({
        typeKey: malformed,
        'left': 10.0,
        'top': 10.0,
        'right': 90.0,
        'bottom': 90.0,
        envelopeKey: {
          'stamps': {
            'geometry': {
              'hlc': '2026-05-27T08:00:00.000Z-0001-author',
              'origin': 'author'
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
      expect(action.boxes.any((b) => b.id == 'malformed'), isFalse,
          reason: 'a malformed _type must not be admitted as a ClassBox');
      await Future<void>.delayed(Duration.zero);
      expect(problems, 0);

      await probSub.cancel();
      backend.disconnect(SyncSection.classBoxes);
    });
  }

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

  // Round-2 cage-match (Tesla): a non-empty but UNPARSEABLE hlc passes the
  // isEmpty check, then throws in _hlc.observe (Hlc.parse) back in the absorb
  // loop — OUTSIDE the per-doc guard — sinking the whole batch. The door now
  // dry-runs the parse so it is quarantined instead.
  test('a non-empty but unparseable hlc is quarantined (would throw in observe)',
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
    await shared.doc('$path/garbagehlc').set({
      'left': 0.0,
      'top': 0.0,
      'right': 10.0,
      'bottom': 10.0,
      envelopeKey: {
        'stamps': {
          'geometry': {'hlc': 'not-an-hlc', 'origin': 'author'} // non-empty garbage
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
    expect(action.boxes.any((b) => b.id == 'garbagehlc'), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(problems, 0,
        reason: 'an unparseable hlc must be quarantined, not DoS the canvas via observe');

    await probSub.cancel();
    backend.disconnect(SyncSection.classBoxes);
  });

  // Round-2 cage-match (Carnot): the projection dry-run must NOT misclassify a
  // valid tombstone as poison. A tombstone's `{_deleted: true}` payload projects
  // to all-defaults, so it passes the door. If it were quarantined, the write
  // path would read a null base and a stale local write would RESURRECT the
  // delete. This locks that in: the tombstone survives the door and the delete
  // is not resurrected by an older concurrent local write.
  test('a tombstone passes the door and is not resurrected by an older local write',
      () async {
    final shared = FakeFirebaseFirestore();
    final authorHlc = HlcManager(nodeId: 'author');
    final older = authorHlc.issue();
    final newer = authorHlc.issue(); // strictly later than `older`

    // A delete authored at `newer` sits on the wire as a tombstone.
    await shared.doc('$path/x').set({
      NodeSchema.tombstoneField: true,
      envelopeKey: {
        'stamps': {
          NodeSchema.tombstoneUnit: {'hlc': newer, 'origin': 'author'}
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

    // A concurrent local write with an OLDER geometry stamp for the same id.
    final local = GraphNode(
      id: 'x',
      type: 'ClassBox',
      payload: const {
        'left': 1.0,
        'top': 1.0,
        'right': 9.0,
        'bottom': 9.0,
        'name': 'Zombie',
      },
      stamps: {'geometry': FieldStamp(hlc: older, origin: 'me')},
    );
    await backend.addGraphNode(local);

    await Future<void>.delayed(Duration.zero);
    expect(problems, 0);
    // The tombstone base passed the door (not quarantined → null), so the merge
    // kept the delete. A resurrected write would have dropped `_deleted`.
    final onWire = await shared.doc('$path/x').get();
    expect(onWire.data()![NodeSchema.tombstoneField], true,
        reason: 'a quarantined tombstone base would resurrect the delete');

    await probSub.cancel();
    backend.disconnect(SyncSection.classBoxes);
  });

  // Round-3 cage-match (Tesla): a self-heal over a poison base must write the
  // LOCAL merge (localExisting ⊔ incoming), not `incoming` alone — otherwise
  // stamps/units that lived only in localExisting are dropped on the wire, and
  // the PR's advertised self-heal silently loses data.
  test('self-heal over a poison base preserves stamps that only localExisting had',
      () async {
    final shared = FakeFirebaseFirestore();
    // A good box with BOTH a geometry and a label stamp.
    await shared.doc('$path/y').set(agentClassBoxDoc(
          hlc: HlcManager(nodeId: 'author'),
          origin: 'author',
          left: 0.0,
          top: 0.0,
          right: 100.0,
          bottom: 60.0,
          name: 'Original',
        ));

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
        .firstWhere((a) => a.boxes.any((b) => b.id == 'y'))
        .timeout(const Duration(seconds: 5));
    backend.connect(SyncSection.classBoxes);
    await projected; // localExisting['y'] now holds {geometry, label}

    // The wire doc is corrupted (foreign/partial write) — the label stamp is now
    // trapped inside an unreadable envelope.
    await shared.doc('$path/y').set({
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

    // A geometry-only local update to the same id.
    final incoming = GraphNode(
      id: 'y',
      type: 'ClassBox',
      payload: const {'left': 5.0, 'top': 5.0, 'right': 55.0, 'bottom': 45.0},
      stamps: {'geometry': FieldStamp(hlc: HlcManager(nodeId: 'me').issue(), origin: 'me')},
    );
    await backend.updateGraphNode(incoming);

    await Future<void>.delayed(Duration.zero);
    expect(problems, 0);
    // The label stamp from localExisting must survive on the wire — writing
    // `incoming` alone (pre-fix) would have left only the geometry stamp.
    final onWire = await shared.doc('$path/y').get();
    final stamps = (onWire.data()![envelopeKey] as Map)['stamps'] as Map;
    expect(stamps.containsKey('label'), isTrue,
        reason: 'self-heal must keep localExisting-only stamps (localMerged), not drop them');

    await probSub.cancel();
    backend.disconnect(SyncSection.classBoxes);
  });

  // Round-4 cage-match (Tesla structural / Carnot #1): mergeNodes fails closed
  // (StateError) on EQUAL stamps with a divergent payload — a shape a foreign
  // producer can craft by replaying a stamp with a different value. That throw
  // is in the absorb loop OUTSIDE the door, so pre-fix it aborted the batch →
  // ProblemPage. The per-doc structural wrap must quarantine it instead.
  test('equal-stamp-divergent-payload (mergeNodes StateError) is quarantined, not a batch DoS',
      () async {
    final shared = FakeFirebaseFirestore();
    final stampHlc = HlcManager(nodeId: 'author').issue(); // one fixed, valid HLC

    Map<String, Object?> docWithLeft(double left) => {
          'left': left,
          'top': 0.0,
          'right': 100.0,
          'bottom': 60.0,
          envelopeKey: {
            'stamps': {
              'geometry': {'hlc': stampHlc, 'origin': 'author'} // SAME stamp both times
            }
          },
        };

    await shared.doc('$path/e').set(docWithLeft(5.0));

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
    final firstProjection = controller.stream
        .where((a) => a is StoreClassBoxesAction)
        .cast<StoreClassBoxesAction>()
        .firstWhere((a) => a.boxes.any((b) => b.id == 'e'))
        .timeout(const Duration(seconds: 5));
    backend.connect(SyncSection.classBoxes);
    await firstProjection; // replica['e'] = {geometry stampHlc, left 5}

    // Same stamp, divergent payload — mergeNodes(existing, incoming) throws.
    await shared.doc('$path/e').set(docWithLeft(99.0));

    await Future<void>.delayed(Duration.zero);
    expect(problems, 0,
        reason: 'a mergeNodes StateError must be quarantined per-doc, not DoS the batch');

    await probSub.cancel();
    backend.disconnect(SyncSection.classBoxes);
  });

  // Round-5 cage-match (Tesla): the equal-stamp/divergent-payload mergeNodes
  // throw exists on the WRITE path too — _writeMerged's transaction merges the
  // remote base against incoming, and pre-fix a StateError there fell through to
  // addProblem (whole-canvas DoS). The sibling structural guard must quarantine
  // the base and self-heal to localMerged instead.
  test('write path: an equal-stamp merge StateError quarantines + self-heals, no DoS',
      () async {
    final shared = FakeFirebaseFirestore();
    // A remote base forging OUR origin ('me') with a fixed hlc, left 5.
    final stampHlc = HlcManager(nodeId: 'me').issue();
    await shared.doc('$path/w').set({
      'left': 5.0,
      'top': 0.0,
      'right': 100.0,
      'bottom': 60.0,
      envelopeKey: {
        'stamps': {
          'geometry': {'hlc': stampHlc, 'origin': 'me'}
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

    // A local write with the SAME stamp but a DIVERGENT payload (left 99) →
    // mergeNodes(remoteNode, incoming) throws in the transaction.
    final incoming = GraphNode(
      id: 'w',
      type: 'ClassBox',
      payload: const {'left': 99.0, 'top': 0.0, 'right': 100.0, 'bottom': 60.0},
      stamps: {'geometry': FieldStamp(hlc: stampHlc, origin: 'me')},
    );
    await backend.updateGraphNode(incoming);

    await Future<void>.delayed(Duration.zero);
    expect(problems, 0,
        reason: 'a write-path merge StateError must quarantine + self-heal, not DoS');
    // Self-heal: our local write landed on the wire.
    final onWire = await shared.doc('$path/w').get();
    expect((onWire.data()!['left'] as num).toDouble(), 99.0);

    await probSub.cancel();
    backend.disconnect(SyncSection.classBoxes);
  });

  // Face (d), flagged across rounds 4-6: a remote doc carrying a Firestore
  // reserved `__.*__` field name must be quarantined at the door (it would 400
  // on our next merge-write-back). Seeded via the raw map, asserting the door's
  // _noReservedFieldNames check fires.
  test('a doc with a reserved __.*__ field name is quarantined', () async {
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
    await shared.doc('$path/reserved').set({
      'left': 0.0,
      'top': 0.0,
      'right': 10.0,
      'bottom': 10.0,
      '__evil__': 'x', // reserved field-name pattern
      envelopeKey: {
        'stamps': {
          'geometry': {
            'hlc': HlcManager(nodeId: 'author').issue(),
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
    expect(action.boxes.any((b) => b.id == 'reserved'), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(problems, 0);

    await probSub.cancel();
    backend.disconnect(SyncSection.classBoxes);
  });
}
