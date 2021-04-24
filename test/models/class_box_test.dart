import 'dart:convert';

import 'package:domain_visualiser/models/domain-objects/domain_object.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Model', () {
    testWidgets('ClassBox ...', (WidgetTester tester) async {
      final classBox = ClassBox(id: 'id', left: 0, top: 0, right: 0, bottom: 0);

      print(jsonEncode(classBox.toJson()));
      expect(classBox is ClassBox, true);
    });
  });
}
