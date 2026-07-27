// A headless **seed writer** that draws a small domain diagram onto the shared
// canvas, demonstrating ADR-0002 (a writer is just an origin + HLC).
//
// SCOPE — read before extending: this REST-PATCHes a full document per box (an
// upsert), NOT the production read-merge-write transaction. So it is a one-shot
// SEED, not a live peer: re-running it after a human edit would clobber that
// human's units. The full CONFLICT-FREE peer semantics (agent envelope merging
// with a concurrent human edit) are exercised for real in
// `test/sync/agent_peer_draws_test.dart`, which feeds this file's exact wire
// bytes through the production `FirestoreBackend`. This tool's job is only to
// make the bytes appear live on a local canvas.
//
// It reuses the production HLC (`package:crdt` via [HlcManager]) and the single
// wire-bytes producer ([agentClassBoxDoc]) — the same map that acceptance test
// consumes — then REST-encodes it to the Firestore emulator.
//
// Prereqs — a Firestore emulator listening on 127.0.0.1:8080. Normally:
//   firebase emulators:start --only auth,firestore
// If that CLI's port pre-check misfires in your environment (it did here), run
// the JAR directly, as lib/main_emulator.dart's header documents:
//   java -jar ~/.cache/firebase/emulators/cloud-firestore-emulator-*.jar \
//        --host=127.0.0.1 --port=8080
// Run:
//   dart run tool/agent_draw.dart
//
// Pure Dart + `dart:io` only (no `http` dep, no Flutter engine).

import 'dart:convert';
import 'dart:io';

import 'package:domain_visualiser/graph/agent_draw_envelope.dart';
import 'package:domain_visualiser/graph/class_box_schema.dart' show classBoxesCollection;
import 'package:domain_visualiser/graph/hlc_manager.dart';

const String _projectId = 'domain-visualiser-app';
// 127.0.0.1, not 'localhost': the emulator JAR binds IPv4 only, and on stacks
// where 'localhost' resolves to ::1 first the write would hit a dead address
// while the canvas (which uses 127.0.0.1) reads fine — a silent one-sided split.
const String _host = '127.0.0.1';
const int _port = 8080;
const String _origin = 'agent-claude';
// Shared with FirestoreBackend.locationOf via the one pure-Dart constant, so the
// writer and the canvas can never drift onto different collections (Wu's catch).
const String _collection = classBoxesCollection;

/// A tiny domain: Order aggregates LineItems, each LineItem points at a Product,
/// an Order belongs to a Customer. Laid out as a 2x2 grid the canvas can render.
const List<Map<String, Object?>> _diagram = [
  {
    'id': 'box-agent-order',
    'name': 'Order',
    'x': 80.0,
    'y': 80.0,
    'methods': ['total()', 'addLine(item)'],
  },
  {
    'id': 'box-agent-customer',
    'name': 'Customer',
    'x': 380.0,
    'y': 80.0,
    'methods': ['orders()', 'fullName()'],
  },
  {
    'id': 'box-agent-lineitem',
    'name': 'LineItem',
    'x': 80.0,
    'y': 300.0,
    'methods': ['subtotal()'],
  },
  {
    'id': 'box-agent-product',
    'name': 'Product',
    'x': 380.0,
    'y': 300.0,
    'methods': ['price()', 'sku()'],
  },
];

/// Recursively encodes a plain Dart value into a Firestore REST `Value`.
/// https://firebase.google.com/docs/firestore/reference/rest/v1/Value
Map<String, Object?> _fsValue(Object? v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': v.toString()};
  if (v is double) return {'doubleValue': v};
  if (v is String) return {'stringValue': v};
  if (v is List) {
    return {
      'arrayValue': {'values': v.map(_fsValue).toList()}
    };
  }
  if (v is Map) {
    return {
      'mapValue': {
        'fields': v.map((k, val) => MapEntry(k.toString(), _fsValue(val)))
      }
    };
  }
  throw ArgumentError('unencodable value: $v (${v.runtimeType})');
}

Uri _docUri(String id) => Uri.parse(
    'http://$_host:$_port/v1/projects/$_projectId/databases/(default)/documents/$_collection/$id');

/// Upserts one document. `Authorization: Bearer owner` is the emulator's admin
/// token — it bypasses `firestore.rules`, so the agent needs no user session.
Future<void> _patch(HttpClient client, String id, Map<String, Object?> doc) async {
  final fields = doc.map((k, v) => MapEntry(k, _fsValue(v)));
  final req = await client.patchUrl(_docUri(id));
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
  req.headers.contentType = ContentType.json;
  req.add(utf8.encode(jsonEncode({'fields': fields})));
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  if (resp.statusCode >= 300) {
    throw StateError('PATCH $id -> ${resp.statusCode}: $body');
  }
  stdout.writeln('  drew  $_collection/$id  (${resp.statusCode})');
}

Future<Map<String, Object?>?> _read(HttpClient client, String id) async {
  final req = await client.getUrl(_docUri(id));
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  if (resp.statusCode == 404) return null;
  if (resp.statusCode >= 300) {
    throw StateError('GET $id -> ${resp.statusCode}: $body');
  }
  return jsonDecode(body) as Map<String, Object?>;
}

Future<void> main(List<String> args) async {
  final hlc = HlcManager(nodeId: _origin);
  final client = HttpClient();

  // Preflight: fail fast with a clear message if the emulator isn't up.
  try {
    await _read(client, 'preflight-probe');
  } on SocketException {
    stderr.writeln(
        'Cannot reach the Firestore emulator at $_host:$_port.\n'
        'Start it first:  firebase emulators:start --only auth,firestore');
    client.close();
    exitCode = 1;
    return;
  }

  stdout.writeln('agent "$_origin" drawing ${_diagram.length} boxes…');
  for (final b in _diagram) {
    final x = b['x'] as double;
    final y = b['y'] as double;
    // Full CRDT envelope (per-merge-unit stamps) — now that the wire keys are
    // legal Firestore field names, this persists to a real backend and the
    // canvas reads it through the normal (non-legacy) envelope path.
    final doc = agentClassBoxDoc(
      hlc: hlc,
      origin: _origin,
      left: x,
      top: y,
      right: x + 200.0,
      bottom: y + 140.0,
      name: b['name'] as String,
      instanceMethods: (b['methods'] as List).cast<String>(),
      userId: _origin,
    );
    await _patch(client, b['id'] as String, doc);
  }

  // Read every box back so the run proves the bytes landed in the shared store
  // (verify, don't assert).
  stdout.writeln('\nreadback from the shared store:');
  for (final b in _diagram) {
    final doc = await _read(client, b['id'] as String);
    final f = doc?['fields'] as Map?;
    String num(String k) =>
        ((f?[k] as Map?)?['doubleValue'] ?? (f?[k] as Map?)?['integerValue'])
            .toString();
    final name = (f?['name'] as Map?)?['stringValue'];
    stdout.writeln(
        '  $name  @ (${num('left')},${num('top')})–(${num('right')},${num('bottom')})');
  }
  stdout.writeln('\ndone — the agent drew a 4-class diagram into the live store.');

  client.close();
}
