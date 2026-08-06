import 'package:codraw/graph/class_box_schema.dart';
import 'package:codraw/graph/community_schemas.dart';
import 'package:codraw/graph/schema_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SchemaRegistry', () {
    test('nodeSchemaFor returns the registered schema for a known type', () {
      expect(defaultRegistry.nodeSchemaFor('ClassBox'), same(classBoxSchema));
      expect(defaultRegistry.hasNodeType('ClassBox'), isTrue);
    });

    test('Slice 1 registers Person and Repo alongside ClassBox', () {
      expect(defaultRegistry.nodeSchemaFor('Person'), same(personSchema));
      expect(defaultRegistry.hasNodeType('Person'), isTrue);
      expect(defaultRegistry.nodeSchemaFor('Repo'), same(repoSchema));
      expect(defaultRegistry.hasNodeType('Repo'), isTrue);
    });

    test('nodeSchemaFor returns null for an unregistered type — NO default', () {
      // The whole point of the nullable lookup: a foreign/unknown type must NOT
      // silently resolve to ClassBox (that was the "guard the window" collapse).
      // 'Comment' is a type no schema registers.
      expect(defaultRegistry.nodeSchemaFor('Comment'), isNull);
      expect(defaultRegistry.hasNodeType('Comment'), isFalse);
    });

    test('edge types are still unregistered — contribution arrives in Slice 2',
        () {
      expect(defaultRegistry.edgeSchemaFor('contribution'), isNull);
      expect(defaultRegistry.hasEdgeType('contribution'), isFalse);
    });
  });
}
