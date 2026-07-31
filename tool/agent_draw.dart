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
// make the bytes appear live on a canvas.
//
// For a RE-RUNNABLE peer that does NOT clobber human edits (create-vs-update
// with an updateMask), see `tool/community_ingest.dart`.
//
// It reuses the production HLC (`package:crdt` via [HlcManager]) and the single
// wire-bytes producer ([agentClassBoxDoc]) — the same map the acceptance test
// consumes — then REST-encodes it to Firestore via the shared machinery in
// `tool/firestore_rest.dart`.
//
// TWO TARGETS:
//   dart run tool/agent_draw.dart            # local Firestore emulator (default)
//   dart run tool/agent_draw.dart --live     # the real domain-visualiser-app
//
// Emulator prereq — a Firestore emulator on 127.0.0.1:8080. Normally:
//   firebase emulators:start --only auth,firestore
// If that CLI's port pre-check misfires (it did here), run the JAR directly:
//   java -jar ~/.cache/firebase/emulators/cloud-firestore-emulator-*.jar \
//        --host=127.0.0.1 --port=8080
//
// --live prereq — `gcloud` authed as an OWNER of the project. An owner OAuth
// token bypasses `firestore.rules` on the REST API, so the agent needs no user
// session. NOTE (remote-input-seam task, face b): the live path writes via raw
// REST and so bypasses the production single write-door
// (`FirestoreBackend._toFirestoreDoc`) and its reserved-name assert. The bytes
// come from the shared [agentClassBoxDoc] producer, which is already
// reserved-name-clean; routing this bypass through the shared validator is
// tracked in the seam-hardening task.
//
// Pure Dart + `dart:io` only (no `http` dep, no Flutter engine).

import 'dart:io';

import 'package:codraw/graph/agent_draw_envelope.dart';
import 'package:codraw/graph/hlc_manager.dart';

import 'firestore_rest.dart';

const String _origin = 'agent-claude';

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

Future<void> main(List<String> args) async {
  final target = await resolveTarget(args);
  final hlc = HlcManager(nodeId: _origin);
  final client = HttpClient();

  // Preflight: fail fast with a clear message if the target isn't reachable.
  try {
    await read(client, target, 'preflight-probe');
  } on SocketException {
    stderr.writeln('Cannot reach ${target.label}.\n'
        'Emulator: start it first (see this file\'s header).');
    client.close();
    exitCode = 1;
    return;
  }

  stdout.writeln(
      'agent "$_origin" drawing ${_diagram.length} boxes → ${target.label}…');
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
    await patch(client, target, b['id'] as String, doc);
  }

  // Read every box back so the run proves the bytes landed in the shared store
  // (verify, don't assert).
  stdout.writeln('\nreadback from the shared store:');
  for (final b in _diagram) {
    final doc = await read(client, target, b['id'] as String);
    final f = doc?['fields'] as Map?;
    String num(String k) =>
        ((f?[k] as Map?)?['doubleValue'] ?? (f?[k] as Map?)?['integerValue'])
            .toString();
    final name = (f?['name'] as Map?)?['stringValue'];
    stdout.writeln(
        '  $name  @ (${num('left')},${num('top')})–(${num('right')},${num('bottom')})');
  }
  stdout.writeln('\ndone — the agent drew a 4-class diagram into ${target.label}.');

  client.close();
}
