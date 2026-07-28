import 'dart:async';

import 'package:domain_visualiser/actions/domain-objects/store_class_boxes_action.dart';
import 'package:domain_visualiser/actions/problems/add_problem_action.dart';
import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/graph/agent_draw_envelope.dart';
import 'package:domain_visualiser/graph/class_box_schema.dart' show envelopeKey;
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
}
