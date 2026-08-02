import 'package:codraw/graph/class_box_schema.dart';
import 'package:codraw/graph/schema_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SchemaRegistry', () {
    test('nodeSchemaFor returns the registered schema for a known type', () {
      expect(defaultRegistry.nodeSchemaFor('ClassBox'), same(classBoxSchema));
      expect(defaultRegistry.hasNodeType('ClassBox'), isTrue);
    });

    test('nodeSchemaFor returns null for an unregistered type — NO default', () {
      // The whole point of the nullable lookup: a foreign/unknown type must NOT
      // silently resolve to ClassBox (that was the "guard the window" collapse).
      expect(defaultRegistry.nodeSchemaFor('Person'), isNull);
      expect(defaultRegistry.hasNodeType('Person'), isFalse);
    });

    test('Slice 0 registers ClassBox alone; no edge types yet', () {
      expect(defaultRegistry.hasNodeType('Repo'), isFalse);
      expect(defaultRegistry.edgeSchemaFor('contribution'), isNull);
      expect(defaultRegistry.hasEdgeType('contribution'), isFalse);
    });
  });
}
