import 'package:domain_visualiser/graph/graph_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

/// An ascent-log terminus edge: `body` (the voice's prose + heat) moves as one
/// unit, `label` (which voice) is independent. Mirrors the ClassBox grain in
/// `graph_envelope_test.dart`, but on an edge.
const _terminusSchema = EdgeSchema(
  type: 'Resonance',
  mergeUnits: {
    'body': ['text', 'temperature'],
    'label': ['voice'],
  },
);

/// Builds a stamp; later [seq] sorts lexicographically after earlier ones.
FieldStamp _stamp(String origin, int seq) => FieldStamp(
    hlc: '2026-07-10T08:00:00.000Z-${seq.toString().padLeft(4, '0')}-$origin',
    origin: origin);

/// An edge from ember A to ember B (a Resonance link), id fixed so replicas
/// share identity. Endpoints stay constant across a merge — that is the point.
GraphEdge _edge({
  required Map<String, Object?> payload,
  required Map<String, FieldStamp> stamps,
  String fromId = 'ember-A',
  String toId = 'ember-B',
}) =>
    GraphEdge(
      id: 'edge-1',
      type: 'Resonance',
      fromId: fromId,
      toId: toId,
      payload: payload,
      stamps: stamps,
    );

void main() {
  group('mergeEdges', () {
    test('concurrent independent-unit edits both survive (no clobber)', () {
      final base = _edge(
        payload: {'text': 'seed', 'temperature': 2, 'voice': 'Maxwell'},
        stamps: {'body': _stamp('seed', 0), 'label': _stamp('seed', 0)},
      );
      // Alice rewrites the body; Bob reassigns the voice. Independent units.
      final alice = _edge(
        payload: {...base.payload, 'text': 'hotter', 'temperature': 4},
        stamps: {...base.stamps, 'body': _stamp('alice', 1)},
      );
      final bob = _edge(
        payload: {...base.payload, 'voice': 'Kelvin'},
        stamps: {...base.stamps, 'label': _stamp('bob', 1)},
      );

      final merged = mergeEdges(alice, bob, _terminusSchema);

      expect(merged.payload['text'], 'hotter', reason: "Alice's body survives");
      expect(merged.payload['voice'], 'Kelvin', reason: "Bob's voice survives");
    });

    test('concurrent body-vs-body: unit is taken whole (no field tearing)', () {
      final alice = _edge(
        payload: {'text': 'a', 'temperature': 1},
        stamps: {'body': _stamp('alice', 1)},
      );
      final bob = _edge(
        payload: {'text': 'b', 'temperature': 5},
        stamps: {'body': _stamp('bob', 2)}, // higher HLC → Bob wins
      );

      final merged = mergeEdges(alice, bob, _terminusSchema);

      // The winning side's body is taken WHOLE — no mix of Alice's text with
      // Bob's temperature.
      expect(merged.payload['text'], 'b');
      expect(merged.payload['temperature'], 5);
    });

    test('delete vs late edit: higher HLC wins through the same path', () {
      final deleted = _edge(
        payload: {'text': 'x', EdgeSchema.tombstoneField: true},
        stamps: {'__tomb__': _stamp('alice', 1)},
      );
      final lateEdit = _edge(
        payload: {'text': 'x', EdgeSchema.tombstoneField: false},
        stamps: {'__tomb__': _stamp('bob', 2)}, // resurrection wins (higher HLC)
      );

      final merged = mergeEdges(deleted, lateEdit, _terminusSchema);
      expect(merged.isDeleted, isFalse, reason: 'later un-delete resurrects');
    });

    test('merge is commutative — replicas converge regardless of order', () {
      final alice = _edge(
        payload: {'voice': 'from-alice'},
        stamps: {'label': _stamp('alice', 1)},
      );
      final bob = _edge(
        payload: {'voice': 'from-bob'},
        stamps: {'label': _stamp('bob', 2)},
      );

      final ab = mergeEdges(alice, bob, _terminusSchema);
      final ba = mergeEdges(bob, alice, _terminusSchema);

      expect(ab.payload['voice'], ba.payload['voice']);
      expect(ab.payload['voice'], 'from-bob', reason: 'higher HLC wins both ways');
    });

    test('endpoints survive a merge unchanged (identity, never merged)', () {
      final alice = _edge(
        payload: {'voice': 'a'},
        stamps: {'label': _stamp('alice', 1)},
      );
      final bob = _edge(
        payload: {'voice': 'b'},
        stamps: {'label': _stamp('bob', 2)},
      );

      final merged = mergeEdges(alice, bob, _terminusSchema);
      expect(merged.fromId, 'ember-A');
      expect(merged.toId, 'ember-B');
    });

    test('round-trips through JSON unchanged (endpoints included)', () {
      final edge = _edge(
        payload: {'text': 'a', 'voice': 'Maxwell', EdgeSchema.tombstoneField: false},
        stamps: {'body': _stamp('a', 1), 'label': _stamp('a', 1)},
      );
      final restored = GraphEdge.fromJson(edge.toJson());
      expect(restored.fromId, 'ember-A');
      expect(restored.toId, 'ember-B');
      expect(restored.type, 'Resonance');
      expect(restored.payload, edge.payload);
      expect(restored.stamps['body']!.hlc, edge.stamps['body']!.hlc);
    });

    test('merging edges with mismatched endpoints throws (immutable identity)', () {
      final a = _edge(
        payload: {'voice': 'a'},
        stamps: {'label': _stamp('a', 1)},
        toId: 'ember-B',
      );
      // Same id, different target — a "moved" edge, which must be delete+recreate.
      final moved = _edge(
        payload: {'voice': 'b'},
        stamps: {'label': _stamp('b', 2)},
        toId: 'ember-C',
      );

      expect(() => mergeEdges(a, moved, _terminusSchema), throwsAssertionError);
    });

    test('Resonance is an inter-ember edge (fromId/toId are distinct embers)', () {
      final resonance = GraphEdge(
        id: 'res-1',
        type: 'Resonance',
        fromId: 'ember-crdt-coedit',
        toId: 'ember-graph-engine',
        payload: {'text': 'this ignites the graph-engine dream', 'temperature': 4},
        stamps: {'body': _stamp('Kelvin', 1)},
      );

      // The cross-ember shape the /ascend design calls for: a terminus edge
      // whose endpoints are two different ember nodes.
      expect(resonance.fromId, isNot(equals(resonance.toId)));
      expect(resonance.type, 'Resonance');
      expect(resonance.payload['temperature'], 4);
    });
  });
}
