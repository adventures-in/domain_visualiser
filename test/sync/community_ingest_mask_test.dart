import 'package:domain_visualiser/graph/agent_draw_envelope.dart';
import 'package:domain_visualiser/graph/class_box_schema.dart' show envelopeKey;
import 'package:domain_visualiser/graph/graph_envelope.dart' show FieldStamp;
import 'package:domain_visualiser/graph/hlc_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves the create-vs-update CRUX: on re-ingest, the agent's masked UPDATE
/// preserves a human's geometry (position AND size). The agent owns the `label`
/// unit; the human owns `geometry` (ADR-0003). The masked update writes ONLY
/// `name` + `_envelope.stamps.label`, so a human drag/resize survives.
///
/// This models Firestore's documented `updateMask` semantics — only the listed
/// leaf paths are written, every other field is preserved:
/// https://firebase.google.com/docs/firestore/reference/rest/v1/projects.databases.documents/patch
/// The live end-to-end proof (real emulator: create → REST human move →
/// re-ingest → readback) runs in the verify step; this test pins the contract
/// deterministically with no network.
Map<String, Object?> _deepCopy(Map<String, Object?> m) => m.map((k, v) =>
    MapEntry(k, v is Map<String, Object?> ? _deepCopy(v) : v));

/// Applies a Firestore `updateMask` PATCH to [existing]: for each dotted path in
/// [fieldPaths], copy that leaf from [patch] into [existing]; leave every other
/// field untouched. (Faithful to the REST contract for the paths this tool uses.)
Map<String, Object?> _applyMask(Map<String, Object?> existing,
    Map<String, Object?> patch, List<String> fieldPaths) {
  final result = _deepCopy(existing);
  for (final fp in fieldPaths) {
    final segs = fp.split('.');
    Object? src = patch;
    for (final s in segs) {
      src = (src as Map<String, Object?>)[s];
    }
    Map<String, Object?> cursor = result;
    for (var i = 0; i < segs.length - 1; i++) {
      cursor = (cursor[segs[i]] ??= <String, Object?>{}) as Map<String, Object?>;
    }
    cursor[segs.last] = src;
  }
  return result;
}

Map<String, Object?> _stamps(Map<String, Object?> doc) =>
    (doc[envelopeKey] as Map<String, Object?>)['stamps'] as Map<String, Object?>;

void main() {
  const agentOrigin = 'agent-github';

  test('the update mask never touches geometry (payload or stamp)', () {
    final u = agentLabelUpdateDoc(
        hlc: HlcManager(nodeId: agentOrigin), origin: agentOrigin, name: 'x');
    expect(u.fieldPaths, ['name', '$envelopeKey.stamps.label']);
    // No geometry field, and no geometry stamp path.
    expect(u.doc.keys, isNot(contains('left')));
    expect(u.doc.keys, isNot(contains('top')));
    expect(_stamps(u.doc).keys, isNot(contains('geometry')));
    expect(u.fieldPaths.any((p) => p.contains('geometry')), isFalse);
    expect(u.fieldPaths.any((p) => p.contains('left')), isFalse);
  });

  test('a human drag+resize survives a re-ingest', () {
    // 1. Agent CREATE: seed geometry (a small box) + label, all agent-stamped.
    final agentHlc = HlcManager(nodeId: agentOrigin);
    final created = agentClassBoxDoc(
      hlc: agentHlc,
      origin: agentOrigin,
      left: 80.0,
      top: 300.0,
      right: 220.0, // width 140
      bottom: 440.0,
      name: 'nickmeinhold',
      userId: agentOrigin,
    );

    // 2. Human DRAGS to a new spot AND RESIZES (geometry unit, human origin).
    final humanHlc = HlcManager(nodeId: 'human-1');
    for (final s in _stamps(created).values) {
      humanHlc.observe((s as Map)['hlc'] as String);
    }
    final humanMoved = _deepCopy(created);
    humanMoved['left'] = 900.0;
    humanMoved['top'] = 120.0;
    humanMoved['right'] = 1000.0; // width shrunk to 100
    humanMoved['bottom'] = 220.0;
    _stamps(humanMoved)['geometry'] =
        FieldStamp(hlc: humanHlc.issue(), origin: 'human-1').toJson();

    // 3. Agent RE-INGEST: masked UPDATE (label only).
    for (final s in _stamps(humanMoved).values) {
      agentHlc.observe((s as Map)['hlc'] as String);
    }
    final update =
        agentLabelUpdateDoc(hlc: agentHlc, origin: agentOrigin, name: 'nickmeinhold');
    final after = _applyMask(humanMoved, update.doc, update.fieldPaths);

    // 4. Geometry (position AND size) is the HUMAN's, untouched by the agent.
    expect(after['left'], 900.0, reason: 'human drag survived');
    expect(after['top'], 120.0);
    expect(after['right'], 1000.0, reason: 'human resize survived (v1: size not re-touched)');
    expect(after['bottom'], 220.0);
    expect((_stamps(after)['geometry'] as Map)['origin'], 'human-1',
        reason: 'geometry stamp still the human\'s');

    // 5. The agent re-owns the label unit with a strictly-later stamp.
    expect(after['name'], 'nickmeinhold');
    expect((_stamps(after)['label'] as Map)['origin'], agentOrigin);
    final createdLabelHlc = (_stamps(created)['label'] as Map)['hlc'] as String;
    final afterLabelHlc = (_stamps(after)['label'] as Map)['hlc'] as String;
    expect(afterLabelHlc.compareTo(createdLabelHlc), greaterThan(0),
        reason: 'the re-ingest label stamp sorts after the create stamp');
  });
}
