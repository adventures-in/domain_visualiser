import 'class_box_schema.dart' show envelopeKey;
import 'graph_envelope.dart';
import 'hlc_manager.dart';

/// Builds the **on-wire Firestore document** for a `ClassBox` authored by an
/// agent peer: the flat payload fields plus an [agentEnvelopeKey] block of
/// per-merge-unit CRDT stamps — byte-for-byte the shape `FirestoreBackend`
/// reads (`_readGraphNodeFromDoc`) and writes (`_toFirestoreDoc`).
///
/// This is the **single producer** of the agent's wire bytes. It is consumed
/// two ways that share nothing but this function:
///   1. the acceptance test feeds the map straight into a `fake_cloud_firestore`
///      and asserts the real `FirestoreBackend` projects it into a `ClassBox`;
///   2. `tool/agent_draw.dart` REST-encodes the same map to the Firestore
///      emulator.
/// Because the consumer in (1) is production code (not this function's inverse),
/// a green test proves the bytes are genuinely consumable — not merely
/// self-consistent (cf. self-referential-codec blindness).
///
/// Pure Dart (only `package:crdt` via [HlcManager] + [FieldStamp]) so it runs
/// under a plain `dart run` with no Flutter engine.
///
/// A partial create is legal: only the units actually authored are stamped
/// (`geometry` always; `label`/`instanceMethods` when supplied). A fresh reader
/// stores the node as-is; a later concurrent human edit LWWs per unit, so an
/// unauthored unit never clobbers a human's field.
Map<String, Object?> agentClassBoxDoc({
  required HlcManager hlc,
  required String origin,
  required double left,
  required double top,
  required double right,
  required double bottom,
  String? name,
  List<String>? instanceMethods,
  String? userId,
  // When false, emit ONLY the flat payload (no [agentEnvelopeKey] block) — the
  // canvas still renders it via `FirestoreBackend`'s legacy-row path. Kept as an
  // option for exercising that path; the full envelope (default) now persists to
  // real Firestore since the wire keys are legal (single-underscore).
  bool includeEnvelope = true,
}) {
  FieldStamp stamp() => FieldStamp(hlc: hlc.issue(), origin: origin);

  final payload = <String, Object?>{
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
    if (name != null) 'name': name,
    if (instanceMethods != null) 'instanceMethods': instanceMethods,
    if (userId != null) 'userId': userId,
  };

  if (!includeEnvelope) return payload;

  final stamps = <String, Object?>{
    'geometry': stamp().toJson(),
    if (name != null) 'label': stamp().toJson(),
    if (instanceMethods != null) 'instanceMethods': stamp().toJson(),
  };

  return <String, Object?>{
    ...payload,
    envelopeKey: <String, Object?>{'stamps': stamps},
  };
}
