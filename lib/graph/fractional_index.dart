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

/// Printable ASCII range used as the "digits" of our fractional alphabet.
/// 0x20 (space, 32) through 0x7e (~, 126). 95 distinct characters, all valid
/// in JSON / Firestore field values, ordered exactly by their code points.
const int _minChar = 0x20;
const int _maxChar = 0x7e;
// Alphabet size = _maxChar - _minChar + 1 = 95 (printable ASCII).
// Documented here for readers; the digit math uses _minChar/_maxChar directly.

/// Canonical seed for the first child of an empty container. Picked as a
/// midpoint of the alphabet so subsequent inserts on either side have room to
/// grow without immediately needing long suffixes. Capital "O" (0x4f) sits
/// almost exactly in the middle of the printable range.
const String firstIndex = 'O';

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
String between(String? before, String? after) {
  if (before == null && after == null) return firstIndex;

  if (before != null && after != null) {
    if (before.compareTo(after) >= 0) {
      throw ArgumentError(
        'fractional_index.between: before ($before) must be strictly less than after ($after)',
      );
    }
  }

  final mid = _midpoint(before, after);
  // Always append a multi-char random tiebreaker so concurrent calls don't
  // collide. A single char gives only ~78 values → birthday collisions show
  // up in low hundreds of concurrent calls. Four chars (~78^4 ≈ 3.7e7) keeps
  // collision probability under 1-in-a-million up to thousands of concurrent
  // peers, which is far past anything our deployment scale needs.
  return '$mid${_randomChar()}${_randomChar()}${_randomChar()}${_randomChar()}';
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
  // either side. Range ~ [0x30..0x7d] (digits..~).
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
