import 'package:codraw/graph/graph_envelope.dart';
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

    test('late edit resurrects: higher-HLC un-delete wins through the tomb unit', () {
      final deleted = _edge(
        payload: {'text': 'x', EdgeSchema.tombstoneField: true},
        stamps: {EdgeSchema.tombstoneUnit: _stamp('alice', 1)},
      );
      final lateEdit = _edge(
        payload: {'text': 'x', EdgeSchema.tombstoneField: false},
        stamps: {EdgeSchema.tombstoneUnit: _stamp('bob', 2)}, // higher HLC
      );

      final merged = mergeEdges(deleted, lateEdit, _terminusSchema);
      expect(merged.isDeleted, isFalse, reason: 'later un-delete resurrects');
    });

    test('late delete wins: higher-HLC tombstone beats an earlier edit (dual)', () {
      final edit = _edge(
        payload: {'text': 'x', EdgeSchema.tombstoneField: false},
        stamps: {EdgeSchema.tombstoneUnit: _stamp('alice', 1)},
      );
      final deleted = _edge(
        payload: {'text': 'x', EdgeSchema.tombstoneField: true},
        stamps: {EdgeSchema.tombstoneUnit: _stamp('bob', 2)}, // higher HLC
      );

      final merged = mergeEdges(edit, deleted, _terminusSchema);
      expect(merged.isDeleted, isTrue, reason: 'later delete wins');
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

      // Full structural equality — not just one payload field. A field-only
      // check would be BLIND to identity (endpoints/type) diverging by argument
      // order, which is exactly the non-commutativity class we must catch.
      expect(ab.toJson(), ba.toJson());
      expect(ab.payload['voice'], 'from-bob', reason: 'higher HLC wins both ways');
    });

    test('partial-payload unit is commutative (winner omits a co-unit field)', () {
      // Alice's body has both fields; Bob's winning body write omits
      // `temperature`. The result must be Bob's field set (text only, NO
      // temperature: null) regardless of argument order — the null-vs-absent
      // trap that a fully-populated test cannot see.
      final alice = _edge(
        payload: {'text': 'a', 'temperature': 1},
        stamps: {'body': _stamp('alice', 1)},
      );
      final bob = _edge(
        payload: {'text': 'b'}, // omits temperature
        stamps: {'body': _stamp('bob', 2)}, // higher HLC → Bob wins
      );

      final ab = mergeEdges(alice, bob, _terminusSchema);
      final ba = mergeEdges(bob, alice, _terminusSchema);
      expect(ab.toJson(), ba.toJson(), reason: 'no null-from-absent asymmetry');
      expect(ab.payload.containsKey('temperature'), isFalse,
          reason: 'winner omitted it → absent, not null');
      expect(ab.payload['text'], 'b');
    });

    test('equal stamps with divergent payload fail closed (corruption)', () {
      // Same (hlc, origin) stamp on both sides but different values — a stamp
      // must identify exactly one write, so this is corruption, not concurrency.
      // wins() is strict, so without the guard this silently keeps local.
      final a = _edge(
        payload: {'text': 'a', 'temperature': 1},
        stamps: {'body': _stamp('same', 1)},
      );
      final b = _edge(
        payload: {'text': 'DIFFERENT', 'temperature': 1},
        stamps: {'body': _stamp('same', 1)}, // identical stamp
      );
      expect(() => mergeEdges(a, b, _terminusSchema), throwsStateError);
    });

    test('idempotent — merging an edge with itself is a no-op', () {
      final edge = _edge(
        payload: {'text': 'a', 'temperature': 3, 'voice': 'Maxwell'},
        stamps: {'body': _stamp('a', 1), 'label': _stamp('a', 1)},
      );
      expect(mergeEdges(edge, edge, _terminusSchema).toJson(), edge.toJson());
    });

    test('associative — (a∘b)∘c == a∘(b∘c) across three replicas', () {
      final a = _edge(
        payload: {'text': 'a', 'temperature': 1, 'voice': 'A'},
        stamps: {'body': _stamp('a', 1), 'label': _stamp('a', 1)},
      );
      final b = _edge(
        payload: {'voice': 'B'},
        stamps: {'label': _stamp('b', 2)},
      );
      final c = _edge(
        payload: {'text': 'c', 'temperature': 9},
        stamps: {'body': _stamp('c', 3)},
      );

      final left = mergeEdges(mergeEdges(a, b, _terminusSchema), c, _terminusSchema);
      final right = mergeEdges(a, mergeEdges(b, c, _terminusSchema), _terminusSchema);
      expect(left.toJson(), right.toJson());
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

    test('divergent identity fails CLOSED at runtime (StateError, not assert)', () {
      final a = _edge(
        payload: {'voice': 'a'},
        stamps: {'label': _stamp('a', 1)},
        toId: 'ember-B',
      );
      // Same id, different target — a "moved" edge, which must be delete+recreate.
      final movedEndpoint = _edge(
        payload: {'voice': 'b'},
        stamps: {'label': _stamp('b', 2)},
        toId: 'ember-C',
      );

      // StateError (a real runtime throw), NOT throwsAssertionError — the guard
      // must fire in release builds too, where asserts are stripped. This is the
      // convergence invariant: divergent identity is corruption, not a merge.
      expect(() => mergeEdges(a, movedEndpoint, _terminusSchema), throwsStateError);
    });

    test('divergent type also fails closed (whole identity tuple guarded)', () {
      final resonance = _edge(
        payload: {'voice': 'a'},
        stamps: {'label': _stamp('a', 1)},
      );
      final asKindle = GraphEdge(
        id: 'edge-1', // same id...
        type: 'Kindle', // ...different type — identity divergence
        fromId: 'ember-A',
        toId: 'ember-B',
        payload: {'voice': 'b'},
        stamps: {'label': _stamp('b', 2)},
      );

      expect(() => mergeEdges(resonance, asKindle, _terminusSchema), throwsStateError);
    });

    test('wrong schema fails closed at runtime (schema.type != edge.type)', () {
      final a = _edge(payload: {'voice': 'a'}, stamps: {'label': _stamp('a', 1)});
      final b = _edge(payload: {'voice': 'b'}, stamps: {'label': _stamp('b', 2)});
      // A schema for a different edge type — its fieldsOf lacks this edge's
      // units, so proceeding would advance stamps without moving fields
      // (irreversible corruption). Must throw, not assert.
      const wrongSchema = EdgeSchema(type: 'Kindle', mergeUnits: {'label': ['voice']});
      expect(() => mergeEdges(a, b, wrongSchema), throwsStateError);
    });

    test('divergent id fails closed (the root identity key, release-critical)', () {
      final a = _edge(payload: {'voice': 'a'}, stamps: {'label': _stamp('a', 1)});
      final b = GraphEdge(
        id: 'edge-2', // different id — distinct edges, must NOT silently merge
        type: 'Resonance',
        fromId: 'ember-A',
        toId: 'ember-B',
        payload: {'voice': 'b'},
        stamps: {'label': _stamp('b', 2)},
      );
      expect(() => mergeEdges(a, b, _terminusSchema), throwsStateError);
    });

    test('divergent fromId fails closed (completes the identity tuple)', () {
      final a = _edge(
        payload: {'voice': 'a'},
        stamps: {'label': _stamp('a', 1)},
        fromId: 'ember-A',
      );
      final movedSource = _edge(
        payload: {'voice': 'b'},
        stamps: {'label': _stamp('b', 2)},
        fromId: 'ember-Z', // same id/toId, different source
      );
      expect(() => mergeEdges(a, movedSource, _terminusSchema), throwsStateError);
    });

    test('concurrent tombstone vs body edit: independent units both resolve', () {
      // Alice deletes the edge; Bob (concurrently) rewrites the body. Tombstone
      // and body are independent units, so both writes resolve by their own HLC
      // — deletion does not clobber the body edit, and vice versa. Order-free.
      final alice = _edge(
        payload: {'text': 'x', EdgeSchema.tombstoneField: true},
        stamps: {EdgeSchema.tombstoneUnit: _stamp('alice', 2)},
      );
      final bob = _edge(
        payload: {'text': 'rewritten', 'temperature': 7},
        stamps: {'body': _stamp('bob', 1)},
      );

      final ab = mergeEdges(alice, bob, _terminusSchema);
      final ba = mergeEdges(bob, alice, _terminusSchema);
      expect(ab.toJson(), ba.toJson(), reason: 'independent units, order-free');
      expect(ab.isDeleted, isTrue, reason: "Alice's delete stands");
      expect(ab.payload['text'], 'rewritten', reason: "Bob's body edit survives");
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
