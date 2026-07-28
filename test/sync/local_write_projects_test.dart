import 'dart:async';

import 'package:domain_visualiser/actions/domain-objects/store_class_boxes_action.dart';
import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/graph/agent_draw_envelope.dart';
import 'package:domain_visualiser/graph/class_box_schema.dart';
import 'package:domain_visualiser/graph/graph_envelope.dart';
import 'package:domain_visualiser/graph/hlc_manager.dart';
import 'package:domain_visualiser/sync/firestore_backend.dart';
import 'package:domain_visualiser/sync/sync_section.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// A *local* write (add / update / tombstone) must re-project onto the canvas
/// immediately — the UI cannot wait on, and must not be starved by, the
/// suppressed Firestore echo of our own write. The pre-existing sync tests only
/// drove the *absorb* (remote-snapshot) path, so this whole-of-loop guarantee
/// was never asserted — which is how "clear" (a delete whose only proof is a
/// live re-render) shipped as a dead button.
///
/// NB: the projection stream is broadcast and does not buffer, so every
/// `nextProjection` future is created BEFORE the write that should satisfy it —
/// otherwise the synchronous emit races ahead of the listener.
void main() {
  final path = FirestoreBackend.locationOf[SyncSection.classBoxes]!;

  GraphNode liveBox(String id, String name, HlcManager hlc, String origin) =>
      GraphNode(
        id: id,
        type: 'ClassBox',
        payload: {
          'left': 10.0,
          'top': 20.0,
          'right': 110.0,
          'bottom': 80.0,
          'name': name,
        },
        stamps: {
          'geometry': FieldStamp(hlc: hlc.issue(), origin: origin),
          'label': FieldStamp(hlc: hlc.issue(), origin: origin),
        },
      );

  /// First projection satisfying [predicate], or a 5s timeout. Subscribes
  /// immediately (call before triggering the write it should observe).
  Future<StoreClassBoxesAction> nextProjection(
    StreamController<ReduxAction> controller,
    bool Function(StoreClassBoxesAction) predicate,
  ) =>
      controller.stream
          .where((a) => a is StoreClassBoxesAction)
          .cast<StoreClassBoxesAction>()
          .firstWhere(predicate)
          .timeout(const Duration(seconds: 5));

  test('updateGraphNode(tombstone) re-projects the canvas WITHOUT the box',
      () async {
    final shared = FakeFirebaseFirestore();
    await shared.doc('$path/box-1').set(agentClassBoxDoc(
          hlc: HlcManager(nodeId: 'author'),
          origin: 'author',
          left: 10.0,
          top: 20.0,
          right: 110.0,
          bottom: 80.0,
          name: 'Order',
        ));

    final controller = StreamController<ReduxAction>.broadcast();
    final backend = FirestoreBackend(
      database: shared,
      eventsController: controller,
      hlc: HlcManager(nodeId: 'me'),
      origin: 'me',
    );

    // Subscribe BEFORE connect so the initial-snapshot projection is captured.
    final present =
        nextProjection(controller, (a) => a.boxes.any((b) => b.id == 'box-1'));
    backend.connect(SyncSection.classBoxes);
    expect((await present).boxes.single.name, 'Order');

    // Subscribe BEFORE the tombstone write. The projection MUST drop the box,
    // driven by the local write (its own echo is suppressed).
    final cleared =
        nextProjection(controller, (a) => a.boxes.every((b) => b.id != 'box-1'));
    await backend.updateGraphNode(
      classBoxTombstone('box-1', hlc: HlcManager(nodeId: 'me'), origin: 'me'),
    );
    expect((await cleared).boxes, isEmpty);

    backend.disconnect(SyncSection.classBoxes);
  });

  test('addGraphNode re-projects the canvas WITH the new box', () async {
    final shared = FakeFirebaseFirestore();
    final controller = StreamController<ReduxAction>.broadcast();
    final hlc = HlcManager(nodeId: 'me');
    final backend = FirestoreBackend(
      database: shared,
      eventsController: controller,
      hlc: hlc,
      origin: 'me',
    );
    backend.connect(SyncSection.classBoxes);

    // Subscribe BEFORE the local create.
    final appeared =
        nextProjection(controller, (a) => a.boxes.any((b) => b.id == 'box-fresh'));
    await backend.addGraphNode(liveBox('box-fresh', 'Fresh', hlc, 'me'));
    expect((await appeared).boxes.single.name, 'Fresh');

    backend.disconnect(SyncSection.classBoxes);
  });
}
