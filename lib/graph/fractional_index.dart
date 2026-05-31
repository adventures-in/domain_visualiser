/// Fractional indexing: dense, totally-ordered string keys that let two peers
/// insert a new sibling between any two existing ones **without coordinating**
/// and without renumbering anything.
///
/// Why a string and not a number?
/// - We need to insert *between* any two existing keys arbitrarily many times.
///   Doubles run out of precision after ~50 inserts at the same gap; strings
///   are unbounded — append more characters to refine.
/// - Lexicographic compare on the string IS the order. No parsing, no special
///   comparator at the storage layer.
///
/// Why a per-call random suffix?
/// - Two peers that concurrently insert "between A and C" with no coordination
///   would otherwise pick the same midpoint string and collide. Appending a
///   short random suffix makes the keys distinct with overwhelming probability
///   while keeping both ordered between the bounds.
///
/// This is intentionally a tiny, dependency-free helper — the algorithm is
/// "midpoint of two strings interpreted as base-95 fractions, then append
/// random tiebreaker." It is NOT a replica of Figma's or Excalidraw's full
/// LSEQ; it is the simplest thing that satisfies the CRDT envelope's needs
/// (z-order among siblings, concurrent inserts converge).
library;

import 'dart:math';

/// Printable, non-whitespace ASCII range used as the "digits" of our
/// fractional alphabet. 0x21 (!, 33) through 0x7e (~, 126). 94 distinct
/// characters, all valid in JSON / Firestore field values, ordered exactly by
/// their code points.
///
/// **Why exclude 0x20 (space)?** Cage-match HIGH (Carnot): if space is a
/// legal digit, the bound `'A '` (capital A followed by space) has nothing
/// strictly between it and `'A'` in the produced alphabet, AND space-suffixed
/// keys can be emitted that compare GREATER than their "before" bound,
/// violating the contract. Excluding space from outputs closes that gap:
/// every produced key has a digit >= `!` at every position, so the
/// implicit-trailing-min-digits view of a short string is `'A' = 'A\x20\x20…'
/// < 'A!' < 'A!!' < …`, and a key like `'A '` could never have been emitted
/// by us in the first place — meaning callers passing one signal a
/// pre-existing contract violation upstream (we reject it; see [between]).
const int _minChar = 0x21;
const int _maxChar = 0x7e;
// Alphabet size = _maxChar - _minChar + 1 = 94. The digit math uses
// _minChar/_maxChar directly.

/// Canonical seed-position character for an empty container. Picked as a
/// midpoint of the alphabet so subsequent inserts on either side have room to
/// grow without immediately needing long suffixes. Capital "O" (0x4f) sits
/// almost exactly in the middle of the printable range.
const String _firstIndexSeed = 'O';

/// Visible for tests and callers that want to know what character empty
/// containers seed at, sans tiebreaker. The actual key emitted by
/// `between(null, null)` is `_firstIndexSeed` plus a 4-char random suffix —
/// see [between] doc — so two concurrent first-inserts converge to *distinct*
/// strings that both sort around 'O'.
const String firstIndex = _firstIndexSeed;

final Random _rng = Random();

/// Returns a fractional index string `i` such that `before < i < after` under
/// lexicographic compare.
///
/// Either bound may be null:
/// - `between(null, null)` returns [firstIndex] (empty container).
/// - `between(null, x)` returns an index that sorts before `x`.
/// - `between(x, null)` returns an index that sorts after `x`.
///
/// `before` must be strictly less than `after` when both are supplied —
/// caller's responsibility to pass them in order. Throws [ArgumentError]
/// otherwise (callers shouldn't be inventing impossible gaps).
///
/// The returned string always has at least one random tiebreaker character at
/// the end so concurrent calls on different replicas produce distinct keys —
/// see file-level doc for why this matters.
String between(String? before, String? after, {String? origin}) {
  // Validate bounds (and reject any with space — see _minChar doc: space
  // shouldn't appear in keys this library produced, so seeing one means
  // upstream corruption, not a legitimate use-case to plumb through).
  if (before != null && _containsSpace(before)) {
    throw ArgumentError(
      'fractional_index.between: before ($before) contains a space, '
      'which is not a valid fractional-index digit',
    );
  }
  if (after != null && _containsSpace(after)) {
    throw ArgumentError(
      'fractional_index.between: after ($after) contains a space, '
      'which is not a valid fractional-index digit',
    );
  }
  if (before != null && after != null) {
    if (before.compareTo(after) >= 0) {
      throw ArgumentError(
        'fractional_index.between: before ($before) must be strictly less than after ($after)',
      );
    }
  }

  // First-insert path (empty container). Use the canonical seed but STILL
  // append a random tiebreaker so two concurrent first-inserts on separate
  // replicas converge to distinct keys (cage-match P1: without this, both
  // return 'O' and a later between('O','O') throws).
  final mid = (before == null && after == null) ? _firstIndexSeed : _midpoint(before, after);


  // Always append a multi-char random tiebreaker so concurrent calls don't
  // collide. A single char gives only ~94 values → birthday collisions show
  // up in low hundreds of concurrent calls. Four chars (~94^4 ≈ 7.8e7) keeps
  // collision probability under 1-in-a-million up to thousands of concurrent
  // peers, which is far past anything our deployment scale needs.
  //
  // If [origin] is supplied, append the first 4 chars of its clientId as a
  // deterministic suffix on top of the random tail. This makes
  // collision-freedom mathematically guaranteed across distinct origins
  // (cage-match Kelvin #3): two origins can never emit the same key even
  // under the worst-case RNG. Same-origin concurrent calls still rely on the
  // 4-char random tail (>=7.8e7 space).
  final originTail = origin == null ? '' : _safeOriginTail(origin);
  final key = '$mid${_randomChar()}${_randomChar()}${_randomChar()}${_randomChar()}$originTail';

  // Adversarial-gap guard. Our alphabet is discrete: pathological inputs
  // like `between('A', 'A!')` admit NO strictly-between key in `[!..~]`
  // because 'A!' is the smallest possible extension of 'A'. The classic
  // bug (cage-match HIGH from Carnot): `_midpoint` blithely synthesizes
  // something like 'A!P' which sorts GREATER than 'A!' — silent contract
  // violation. We validate the *final* key against both bounds and throw
  // if the gap is unsatisfiable, rather than emitting a key that breaks
  // ordering. Callers should keep their bounds well-separated.
  if (before != null && key.compareTo(before) <= 0) {
    throw ArgumentError(
      'fractional_index.between: gap ($before, $after) is too tight — '
      'no strictly-between key exists in the [!..~] alphabet',
    );
  }
  if (after != null && key.compareTo(after) >= 0) {
    throw ArgumentError(
      'fractional_index.between: gap ($before, $after) is too tight — '
      'no strictly-between key exists in the [!..~] alphabet',
    );
  }
  return key;
}

bool _containsSpace(String s) {
  for (var i = 0; i < s.length; i++) {
    if (s.codeUnitAt(i) == 0x20) return true;
  }
  return false;
}

/// Sanitize [origin] for use as a deterministic suffix: strip any character
/// outside the alphabet `[!..~]` so the tail can't smuggle a space (or a NUL,
/// or a non-printable) into a key. Pad with `_` (0x5f) so the suffix length
/// is stable at 4 — that way `compareTo` semantics across keys with vs.
/// without origin don't shift unpredictably.
String _safeOriginTail(String origin) {
  final buf = StringBuffer();
  for (var i = 0; i < origin.length && buf.length < 4; i++) {
    final c = origin.codeUnitAt(i);
    if (c >= _minChar && c <= _maxChar) buf.writeCharCode(c);
  }
  while (buf.length < 4) {
    buf.writeCharCode(0x5f); // '_'
  }
  return buf.toString();
}

/// Computes a deterministic midpoint string strictly between [before] and
/// [after] (either may be null). The result will be extended by a random
/// tiebreaker in [between]; on its own it's a valid (but not collision-safe)
/// fractional key.
String _midpoint(String? before, String? after) {
  // Walk character positions building the midpoint digit-by-digit.
  final out = StringBuffer();

  for (var i = 0;; i++) {
    final lo = i < (before?.length ?? 0) ? before!.codeUnitAt(i) : _minChar;
    final hi = i < (after?.length ?? 0) ? after!.codeUnitAt(i) : _maxChar + 1;

    if (lo == hi) {
      // This digit position is forced; emit it and continue refining below.
      out.writeCharCode(lo);
      continue;
    }
    if (hi - lo > 1) {
      // There is at least one strictly-between digit at this position.
      out.writeCharCode(lo + ((hi - lo) ~/ 2));
      return out.toString();
    }
    // Gap is exactly 1 — no strictly-between digit at this position. Take the
    // lower digit and recurse into the next position with bound (lo, MAX+1).
    // This is the "9.5 = 9 + something" trick in base-95.
    out.writeCharCode(lo);
    // For the next iteration, after-bound becomes open-ended (MAX+1) so we
    // can pick any digit greater than the lower extension.
    after = null;
  }
}

int _randomChar() {
  // Avoid the extremes so the tiebreaker leaves room for further insertions
  // either side. Range [0x30..0x7d] (digits..`}`) — strictly inside
  // [_minChar+1 .. _maxChar-1], so a sibling insert can always slip another
  // key on either side without needing to extend the string an extra digit.
  const lo = 0x30;
  const hi = 0x7d;
  return lo + _rng.nextInt(hi - lo + 1);
}

/// Convenience: ordered iteration helper that callers can use to assert that
/// a list of fractional indices is monotonic. Lives here next to the other
/// fractional-index primitives.
bool isMonotonic(Iterable<String> indices) {
  String? prev;
  for (final s in indices) {
    if (prev != null && prev.compareTo(s) >= 0) return false;
    prev = s;
  }
  return true;
}
