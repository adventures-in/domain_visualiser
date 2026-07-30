// Shared Firestore REST machinery for the headless agent-peer tools
// (`agent_draw.dart`, `community_ingest.dart`). Extracted verbatim from
// `agent_draw.dart` so the two tools cannot drift on the wire encoding, the
// emulator-vs-`--live` target split, or the owner-token auth path.
//
// Pure Dart + `dart:io` only (no `http` dep, no Flutter engine) so both tools
// run under a plain `dart run`.

import 'dart:convert';
import 'dart:io';

import 'package:domain_visualiser/graph/class_box_schema.dart'
    show classBoxesCollection;

const String projectId = 'domain-visualiser-app';
// 127.0.0.1, not 'localhost': the emulator JAR binds IPv4 only, and on stacks
// where 'localhost' resolves to ::1 first the write would hit a dead address
// while the canvas (which uses 127.0.0.1) reads fine — a silent one-sided split.
const String emulatorHost = '127.0.0.1';
const int emulatorPort = 8080;
// The gcloud account that OWNS domain-visualiser-app (its owner OAuth token is
// what bypasses security rules on the --live REST path).
const String liveOwnerAccount = 'nick.meinhold@gmail.com';
// Shared with FirestoreBackend.locationOf via the one pure-Dart constant, so the
// writer and the canvas can never drift onto different collections.
const String collection = classBoxesCollection;

/// Where an agent writes and how it authenticates. Both targets speak the same
/// Firestore REST document API; only the base URL and bearer differ.
class FirestoreTarget {
  FirestoreTarget({required this.base, required this.bearer, required this.label});

  /// `.../databases/(default)/documents` — the collection/id is appended.
  final String base;
  final String bearer;
  final String label;

  Uri docUri(String id) => Uri.parse('$base/$collection/$id');
}

/// Resolves the emulator (default) or `--live` real project target.
Future<FirestoreTarget> resolveTarget(List<String> args) async {
  if (!args.contains('--live')) {
    return FirestoreTarget(
      base:
          'http://$emulatorHost:$emulatorPort/v1/projects/$projectId/databases/(default)/documents',
      bearer: 'owner', // emulator admin token
      label: 'emulator $emulatorHost:$emulatorPort',
    );
  }
  final token = await gcloudAccessToken(liveOwnerAccount);
  return FirestoreTarget(
    base:
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents',
    bearer: token,
    label: 'LIVE firestore.googleapis.com/$projectId',
  );
}

/// Owner OAuth access token via gcloud. Fetched through [Process] (never argv
/// or env) so the short-lived token stays out of the process table and logs.
Future<String> gcloudAccessToken(String account) async {
  final r = await Process.run(
      'gcloud', ['auth', 'print-access-token', '--account', account]);
  if (r.exitCode != 0) {
    throw StateError(
        'gcloud print-access-token failed for $account: ${r.stderr}');
  }
  return (r.stdout as String).trim();
}

/// Recursively encodes a plain Dart value into a Firestore REST `Value`.
/// https://firebase.google.com/docs/firestore/reference/rest/v1/Value
Map<String, Object?> fsValue(Object? v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': v.toString()};
  if (v is double) return {'doubleValue': v};
  if (v is String) return {'stringValue': v};
  if (v is List) {
    return {
      'arrayValue': {'values': v.map(fsValue).toList()}
    };
  }
  if (v is Map) {
    return {
      'mapValue': {
        'fields': v.map((k, val) => MapEntry(k.toString(), fsValue(val)))
      }
    };
  }
  throw ArgumentError('unencodable value: $v (${v.runtimeType})');
}

/// Full-document upsert against [target] (no updateMask — replaces the doc).
/// This is a CREATE/seed write: the whole [doc] lands. On an existing doc it
/// would clobber every field, so callers use it only for 404 → create.
Future<void> patch(HttpClient client, FirestoreTarget target, String id,
    Map<String, Object?> doc) async {
  final fields = doc.map((k, v) => MapEntry(k, fsValue(v)));
  final req = await client.patchUrl(target.docUri(id));
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${target.bearer}');
  req.headers.contentType = ContentType.json;
  req.add(utf8.encode(jsonEncode({'fields': fields})));
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  if (resp.statusCode >= 300) {
    throw StateError('PATCH $id -> ${resp.statusCode}: $body');
  }
  stdout.writeln('  drew  $collection/$id  (${resp.statusCode})');
}

/// Atomic CREATE against [target]: writes [doc] ONLY if the document does not
/// already exist (Firestore REST `currentDocument.exists=false` precondition).
/// Returns true on create; false if the doc already exists (precondition failed,
/// HTTP 409/412) so the caller can fall back to a masked update instead of a
/// full-document PATCH that would clobber a human's geometry. Throws on any other
/// non-2xx.
///
/// This removes the read-then-write race in a re-runnable poller: a doc that
/// appears between a caller's 404-read and this create (an overlapping poll, or a
/// human dragging a just-created node) can no longer be overwritten — the create
/// fails closed and the caller updates instead. Kills the coupling rather than
/// reasoning about who else writes the id.
/// https://firebase.google.com/docs/firestore/reference/rest/v1/projects.databases.documents/patch
Future<bool> createIfAbsent(HttpClient client, FirestoreTarget target, String id,
    Map<String, Object?> doc) async {
  final fields = doc.map((k, v) => MapEntry(k, fsValue(v)));
  final uri = target.docUri(id).replace(queryParameters: {
    'currentDocument.exists': 'false',
  });
  final req = await client.patchUrl(uri);
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${target.bearer}');
  req.headers.contentType = ContentType.json;
  req.add(utf8.encode(jsonEncode({'fields': fields})));
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  if (resp.statusCode == 409 || resp.statusCode == 412) {
    stdout.writeln('  exists  $collection/$id  (${resp.statusCode}) — '
        'falling back to masked update');
    return false;
  }
  if (resp.statusCode >= 300) {
    throw StateError('CREATE $id -> ${resp.statusCode}: $body');
  }
  stdout.writeln('  drew  $collection/$id  (${resp.statusCode})');
  return true;
}

/// Masked PATCH against [target]: only the field paths in [fieldPaths] are
/// written; every other field on the existing doc is left untouched. This is the
/// UPDATE path — it must cover ONLY agent-owned fields (`name` + its stamp) so a
/// human's geometry (position/size) survives every poll (ADR-0003 authority
/// partition). [doc] must contain a value at each masked leaf.
///
/// A nested leaf uses Firestore field-path dot syntax (`_envelope.stamps.label`);
/// each segment here matches `[A-Za-z_][A-Za-z0-9_]*` so no backtick-quoting is
/// needed. The mask semantics (masked leaves replaced, siblings preserved) are
/// documented at
/// https://firebase.google.com/docs/firestore/reference/rest/v1/projects.databases.documents/patch
Future<void> patchMasked(HttpClient client, FirestoreTarget target, String id,
    Map<String, Object?> doc, List<String> fieldPaths) async {
  final fields = doc.map((k, v) => MapEntry(k, fsValue(v)));
  final uri = target.docUri(id).replace(queryParameters: {
    'updateMask.fieldPaths': fieldPaths,
  });
  final req = await client.patchUrl(uri);
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${target.bearer}');
  req.headers.contentType = ContentType.json;
  req.add(utf8.encode(jsonEncode({'fields': fields})));
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  if (resp.statusCode >= 300) {
    throw StateError('PATCH(mask) $id -> ${resp.statusCode}: $body');
  }
  stdout.writeln('  updated  $collection/$id  (${resp.statusCode}) '
      'mask=[${fieldPaths.join(", ")}]');
}

/// GETs a document; returns null on 404, throws on other non-2xx.
Future<Map<String, Object?>?> read(
    HttpClient client, FirestoreTarget target, String id) async {
  final req = await client.getUrl(target.docUri(id));
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${target.bearer}');
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  if (resp.statusCode == 404) return null;
  if (resp.statusCode >= 300) {
    throw StateError('GET $id -> ${resp.statusCode}: $body');
  }
  return jsonDecode(body) as Map<String, Object?>;
}
