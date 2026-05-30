import 'dart:async';

import 'package:domain_visualiser/actions/domain-objects/add_class_box_action.dart';
import 'package:domain_visualiser/actions/domain-objects/update_domain_action.dart';
import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/enums/database/database_section_enum.dart';
import 'package:domain_visualiser/graph/class_box_schema.dart';
import 'package:domain_visualiser/graph/graph_envelope.dart';
import 'package:domain_visualiser/graph/hlc_manager.dart';
import 'package:domain_visualiser/middleware/domain-objects/add_class_box_middleware.dart';
import 'package:domain_visualiser/middleware/domain-objects/update_domain_middleware.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/models/domain-objects/domain_object.dart';
import 'package:domain_visualiser/reducers/app_reducer.dart';
import 'package:domain_visualiser/services/auth_service.dart';
import 'package:domain_visualiser/sync/graph_sync_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:redux/redux.dart';

/// Captures every call made into a [GraphSyncBackend] so middleware behaviour
/// can be asserted in isolation, without Firestore or the network.
class FakeGraphSyncBackend implements GraphSyncBackend {
  final addedNodes = <GraphNode>[];
  final updatedNodes = <GraphNode>[];
  final addedLegacy = <DomainObject>[];
  final updatedLegacy = <DomainObject>[];
  final _controller = StreamController<ReduxAction>.broadcast();

  @override
  Stream<ReduxAction> get actionStream => _controller.stream;

  @override
  void connect(DatabaseSectionEnum section) {}

  @override
  void disconnect(DatabaseSectionEnum section) {}

  @override
  Future<void> addNode(DomainObject node) async => addedLegacy.add(node);

  @override
  Future<void> updateNode(DomainObject node) async => updatedLegacy.add(node);

  @override
  Future<void> addGraphNode(GraphNode node) async => addedNodes.add(node);

  @override
  Future<void> updateGraphNode(GraphNode node) async => updatedNodes.add(node);
}

/// AuthService stub: getCurrentUserId is the only call paths exercised here
/// hit, so we return a fixed value and otherwise let calls throw to surface
/// any accidental coupling.
class _StubAuthService implements AuthService {
  @override
  Future<String?> getCurrentUserId() async => 'test-user';

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'unexpected call to AuthService.${invocation.memberName}');
}

ClassBox _box({
  String id = 'box-1',
  double left = 0,
  double top = 0,
  double right = 10,
  double bottom = 10,
  String? name,
}) =>
    ClassBox(
        id: id,
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        name: name);

void main() {
  group('AddClassBoxMiddleware', () {
    test('emits a stamped envelope with every merge unit', () async {
      final backend = FakeGraphSyncBackend();
      final hlc = HlcManager(nodeId: 'origin-A');
      final store = Store<AppState>(
        appReducer,
        initialState: AppState.init(),
        middleware: [
          AddClassBoxMiddleware(backend, _StubAuthService(), hlc, 'origin-A'),
        ],
      );

      store.dispatch(AddClassBoxAction(_box(name: 'Hello')));
      // Let the async middleware complete.
      await Future<void>.delayed(Duration.zero);

      expect(backend.addedNodes, hasLength(1));
      final node = backend.addedNodes.single;
      // All declared merge units stamped, all by us.
      expect(node.stamps.keys, containsAll(<String>[
        'geometry',
        'label',
        'staticMethods',
        'instanceMethods',
        'staticVariables',
        'instanceVariables',
      ]));
      for (final s in node.stamps.values) {
        expect(s.origin, 'origin-A');
        expect(s.hlc, isNotEmpty);
      }
      expect(node.payload['name'], 'Hello');
    });
  });

  group('UpdateDomainMiddleware (partial stamping)', () {
    test('only the changed unit is restamped', () async {
      final backend = FakeGraphSyncBackend();
      final hlc = HlcManager(nodeId: 'origin-A');
      final initial = _box(name: 'A');
      final store = Store<AppState>(
        appReducer,
        initialState: AppState.init().copyWith(classBoxes: [initial].lock),
        middleware: [
          UpdateDomainMiddleware(backend, hlc, 'origin-A'),
        ],
      );

      // Drag only — geometry should be the sole stamped unit.
      store.dispatch(UpdateDomainAction(
          initial.copyWith(left: 100.0, right: 110.0)));
      await Future<void>.delayed(Duration.zero);

      expect(backend.updatedNodes, hasLength(1));
      final stamped = backend.updatedNodes.single;
      expect(stamped.stamps.keys, ['geometry']);
      expect(stamped.payload['left'], 100.0);
    });

    test('no-op update emits nothing (skips empty envelope)', () async {
      final backend = FakeGraphSyncBackend();
      final hlc = HlcManager(nodeId: 'origin-A');
      final initial = _box(name: 'A');
      final store = Store<AppState>(
        appReducer,
        initialState: AppState.init().copyWith(classBoxes: [initial].lock),
        middleware: [
          UpdateDomainMiddleware(backend, hlc, 'origin-A'),
        ],
      );

      store.dispatch(UpdateDomainAction(initial)); // identical payload
      await Future<void>.delayed(Duration.zero);

      expect(backend.updatedNodes, isEmpty,
          reason: 'a no-op update must not generate an envelope-less echo');
    });
  });

  group('end-to-end CRDT convergence (no Firestore)', () {
    test('concurrent drag (Alice) + rename (Bob): both edits survive', () {
      // Both replicas start from the same base.
      final base = classBoxToGraphNode(
        _box(name: 'A'),
        hlc: HlcManager(nodeId: 'seed'),
        origin: 'seed',
      );

      final aliceHlc = HlcManager(nodeId: 'alice');
      final bobHlc = HlcManager(nodeId: 'bob');
      // Each catches up on the shared base.
      for (final s in base.stamps.values) {
        aliceHlc.observe(s.hlc);
        bobHlc.observe(s.hlc);
      }

      // Alice drags.
      final aliceUpdate = classBoxToGraphNodePartial(
        updated: _box(left: 100, right: 110, name: 'A'),
        previous: _box(name: 'A'),
        hlc: aliceHlc,
        origin: 'alice',
      );
      // Bob renames.
      final bobUpdate = classBoxToGraphNodePartial(
        updated: _box(name: 'B'),
        previous: _box(name: 'A'),
        hlc: bobHlc,
        origin: 'bob',
      );

      // Apply Alice's update to base, then merge Bob's; and vice versa.
      final aliceFirst = mergeNodes(
          mergeNodes(base, aliceUpdate, classBoxSchema),
          bobUpdate,
          classBoxSchema);
      final bobFirst = mergeNodes(
          mergeNodes(base, bobUpdate, classBoxSchema),
          aliceUpdate,
          classBoxSchema);

      expect(aliceFirst.payload['left'], 100.0,
          reason: "Alice's drag survives concurrent rename");
      expect(aliceFirst.payload['name'], 'B',
          reason: "Bob's rename survives concurrent drag");
      // Convergence: independent of merge order.
      expect(aliceFirst.payload['left'], bobFirst.payload['left']);
      expect(aliceFirst.payload['name'], bobFirst.payload['name']);
    });
  });

  group('echo-suppression', () {
    test('a pure local echo applied to its own writer changes nothing', () {
      final hlc = HlcManager(nodeId: 'origin-A');
      final mine = classBoxToGraphNode(
        _box(name: 'A'),
        hlc: hlc,
        origin: 'origin-A',
      );
      // Simulate Firestore echoing OUR write back at us: identical envelope.
      // Merging it with our local replica must yield the same stamps.
      final merged = mergeNodes(mine, mine, classBoxSchema);
      expect(merged.stamps.length, mine.stamps.length);
      for (final entry in merged.stamps.entries) {
        expect(entry.value.hlc, mine.stamps[entry.key]!.hlc);
        expect(entry.value.origin, 'origin-A');
      }
      // And every stamp's origin matches our id — the pure-echo gate fires.
      expect(merged.stamps.values.every((s) => s.origin == 'origin-A'),
          isTrue);
    });
  });
}

