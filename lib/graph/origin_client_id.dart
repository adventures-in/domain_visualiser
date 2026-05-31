import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Provides this client's **stable origin id** — the string written into every
/// [FieldStamp.origin] this app emits and the basis for echo-suppression.
///
/// Why a dedicated id (rather than the Firebase Auth uid):
/// - It must exist **before** sign-in (so the first stamp emitted at app start
///   has an origin) and stay stable **across** sign-out/sign-in (so HLCs we've
///   already issued aren't suddenly compared against a different origin).
/// - One human signed in on two devices is **two writers** in CRDT terms —
///   their concurrent edits need to disambiguate, and the Auth uid would alias
///   them into one origin and break tie-breaking.
///
/// Persisted in `shared_preferences` under [_key]; generated once on first call.
abstract interface class OriginClientIdProvider {
  Future<String> get();
}

class SharedPreferencesOriginClientId implements OriginClientIdProvider {
  static const String _key = 'graph.originClientId';

  String? _cached;

  @override
  Future<String> get() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_key, id);
    }
    _cached = id;
    return id;
  }
}

/// In-memory provider for tests and any non-Flutter context. Generates one id
/// per instance; pass a fixed [id] to script multi-replica scenarios.
class InMemoryOriginClientId implements OriginClientIdProvider {
  InMemoryOriginClientId([String? id]) : _id = id ?? const Uuid().v4();
  final String _id;

  @override
  Future<String> get() async => _id;
}
