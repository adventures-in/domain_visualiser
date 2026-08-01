import 'class_box_schema.dart';
import 'graph_envelope.dart';

/// The single source of truth mapping a doc's declared `type` discriminator to
/// the [NodeSchema] / [EdgeSchema] its merge units live under.
///
/// **Total over REGISTERED types only** — there is deliberately NO unknown→ClassBox
/// (or unknown→contribution) fallback. A default here would be "guard the window":
/// any call site that reached the registry with an unregistered type would silently
/// merge a foreign doc under the wrong schema and drop its fields (the exact silent
/// field loss #2432 exists to close). Instead, absence-means-ClassBox is resolved in
/// EXACTLY one place — the reader ([FirestoreBackend._readGraphNodeFromDoc], which
/// stamps `'ClassBox'` onto a doc carrying no `_type`) — and the trust-boundary door
/// quarantines a *present-but-unregistered* type before any merge/projection. By the
/// time any code asks the registry for a schema, the type is a concrete admitted
/// string.
///
/// Slice 0 (this cut) registers **ClassBox alone** — a provably zero-behavior-change
/// refactor. Person/Repo/contribution are registered in a later slice; registering
/// them here would make the (still un-tempered) typed-merge/upgrade path reachable.
class SchemaRegistry {
  const SchemaRegistry(this._nodes, this._edges);

  final Map<String, NodeSchema> _nodes;
  final Map<String, EdgeSchema> _edges;

  /// The [NodeSchema] for [type], or null if [type] is not registered. Callers
  /// MUST treat null as "quarantine" — never substitute a default.
  NodeSchema? nodeSchemaFor(String type) => _nodes[type];

  /// The [EdgeSchema] for [type], or null if not registered. Edges have no default:
  /// there are zero legacy edge docs, so an absent/unknown edge type is a quarantine.
  EdgeSchema? edgeSchemaFor(String type) => _edges[type];

  bool hasNodeType(String type) => _nodes.containsKey(type);
  bool hasEdgeType(String type) => _edges.containsKey(type);
}

/// The default registry used by [FirestoreBackend] when none is injected.
///
/// Slice 0: ClassBox is the only registered node type; no edge types yet.
final SchemaRegistry defaultRegistry = SchemaRegistry(
  <String, NodeSchema>{'ClassBox': classBoxSchema},
  const <String, EdgeSchema>{},
);
