import 'package:crdt/crdt.dart';

import 'graph_envelope.dart';

/// Issues Hybrid Logical Clock timestamps and keeps the local clock advanced
/// past every HLC the app has *observed* on the wire.
///
/// Wraps `package:crdt`'s [Hlc] with the small bit of state any CRDT writer
/// needs: a monotonically-increasing local clock that "catches up" whenever a
/// remote stamp with a higher HLC arrives. Lifting this here (rather than
/// depending on Engram) keeps domvis dependency-free of another app — see
/// `docs/adr/0001-graph-envelope.md`, rule-of-three.
///
/// Threading: Dart isolate model. The store, the Firestore listener, and the
/// middleware all run on the same isolate; no locks needed.
class HlcManager {
  HlcManager({required this.nodeId, DateTime Function()? now})
      : _now = now ?? DateTime.now,
        _last = Hlc.zero(nodeId);

  /// The origin id baked into every HLC this manager mints. Must match the
  /// string the app writes into [FieldStamp.origin].
  final String nodeId;

  final DateTime Function() _now;
  Hlc _last;

  /// Issues a fresh, monotonically-increasing HLC.
  ///
  /// `Hlc.increment` advances past the local clock, ensuring the new stamp
  /// sorts strictly after any HLC previously issued by this manager or
  /// observed via [observe].
  HlcString issue() {
    _last = _last.increment(wallTime: _now().toUtc());
    return _last.toString();
  }

  /// True if [candidate] is a well-formed HLC that [observe] can parse.
  ///
  /// The remote-input trust boundary uses this to quarantine a doc whose stamp
  /// carries a non-empty but UNPARSEABLE hlc BEFORE it reaches [observe] —
  /// which calls `Hlc.parse` in the absorb loop OUTSIDE any per-doc guard, so a
  /// throw there would sink the whole snapshot batch to ProblemPage. Non-empty
  /// is not enough; parseable is the real precondition for ordering.
  static bool isValidHlc(HlcString candidate) {
    try {
      Hlc.parse(candidate);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Advances the local clock past [remote] without issuing a new stamp.
  /// Call this for every remote HLC the app observes so the next [issue] sorts
  /// strictly after everyone we've heard from.
  ///
  /// Silently no-ops if [remote] was minted by this client (`package:crdt`
  /// rejects merging an HLC with the same nodeId to catch duplicate-origin
  /// bugs — but seeing our own stamps come back via the Firestore echo is
  /// normal, not a bug).
  void observe(HlcString remote) {
    final remoteHlc = Hlc.parse(remote);
    if (remoteHlc.nodeId == nodeId) return;
    try {
      _last = _last.merge(remoteHlc, wallTime: _now().toUtc());
    } on ClockDriftException catch (e) {
      // Remote clock is too far ahead — drop the observation rather than
      // poison the local clock; next local `issue` will still advance off the
      // local wall time. Log a breadcrumb so a real-world drift incident is
      // visible without breaking the merge.
      // ignore: avoid_print
      print('[HlcManager] dropped remote HLC from ${remoteHlc.nodeId}: $e '
          '(local=$_last)');
    }
  }
}
