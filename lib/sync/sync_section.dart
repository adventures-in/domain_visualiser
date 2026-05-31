import 'package:freezed_annotation/freezed_annotation.dart';

/// Logical section of the synced graph.
///
/// Used by [GraphSyncBackend] (and implementations like
/// `FirestoreBackend`) to identify which slice of the graph
/// a connect/disconnect call refers to. This is a
/// transport-agnostic vocabulary — it names *what* is being
/// synced, not *where* it is stored. JSON values are kept
/// stable for backward compatibility with any persisted data.
enum SyncSection {
  @JsonValue('PROFILE_DATA')
  profile,
  @JsonValue('CLASS_BOXES')
  classBoxes,
}
