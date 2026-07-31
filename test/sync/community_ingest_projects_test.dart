import 'dart:async';

import 'package:codraw/actions/domain-objects/store_class_boxes_action.dart';
import 'package:codraw/actions/redux_action.dart';
import 'package:codraw/graph/agent_draw_envelope.dart';
import 'package:codraw/graph/community_projection.dart';
import 'package:codraw/graph/hlc_manager.dart';
import 'package:codraw/sync/firestore_backend.dart';
import 'package:codraw/sync/sync_section.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Acceptance test for the community-ingest stepping stone: the boxes the
/// projection computes, encoded as the agent's wire bytes via the single
/// producer [agentClassBoxDoc], must project onto a human canvas through the
/// real [FirestoreBackend] — exactly like `agent_peer_draws_test`, but for
/// `origin = agent-github` and a Person box. A pass proves the projected bytes
/// are genuinely consumable, not merely self-consistent.
void main() {
  const agentOrigin = 'agent-github';
  final path = '${FirestoreBackend.locationOf[SyncSection.classBoxes]}';

  test('a projected community box lands as a ClassBox on a human canvas',
      () async {
    // A tiny org: two people share one repo (>=2 humans → included).
    final projection = projectCommunity(
      repos: const [GhRepo(name: 'chat_app', id: 100, fork: false)],
      contributorsByRepo: const {
        'chat_app': [
          GhContributor(
              login: 'nickmeinhold',
              id: 1,
              type: GhContributorType.user,
              contributions: 40),
          GhContributor(
              login: 'Jei',
              id: 2,
              type: GhContributorType.user,
              contributions: 19),
        ],
      },
    );
    final nick = projection.people.firstWhere((b) => b.id == 'gh-person-1');

    final shared = FakeFirebaseFirestore();
    final agentHlc = HlcManager(nodeId: agentOrigin);
    final doc = agentClassBoxDoc(
      hlc: agentHlc,
      origin: agentOrigin,
      left: nick.left,
      top: nick.top,
      right: nick.right,
      bottom: nick.bottom,
      name: nick.name,
      userId: agentOrigin,
    );
    await shared.doc('$path/${nick.id}').set(doc);

    final controller = StreamController<ReduxAction>();
    final projected = Completer<StoreClassBoxesAction>();
    final sub = controller.stream
        .where((a) => a is StoreClassBoxesAction)
        .cast<StoreClassBoxesAction>()
        .listen((a) {
      if (!projected.isCompleted && a.boxes.any((b) => b.id == nick.id)) {
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

    final action = await projected.future.timeout(const Duration(seconds: 5));
    final box = action.boxes.singleWhere((b) => b.id == nick.id);
    expect(box.name, 'nickmeinhold');
    expect(box.left, nick.left);
    expect(box.top, nick.top);
    expect(box.right, nick.right);
    expect(box.bottom, nick.bottom);

    await sub.cancel();
    human.disconnect(SyncSection.classBoxes);
  });
}
