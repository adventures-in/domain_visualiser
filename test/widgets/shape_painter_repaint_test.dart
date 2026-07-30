import 'package:domain_visualiser/models/domain-objects/domain_object.dart';
import 'package:domain_visualiser/widgets/drawing/drawing_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ShapePainter painterFor(List<ClassBox> boxes) => ShapePainter(
      boxes,
      null,
      null,
      Paint(),
      Paint(),
    );

ClassBox box({required String id, String? name, double right = 100}) => ClassBox(
      id: id,
      left: 0,
      top: 0,
      right: right,
      bottom: 100,
      name: name,
    );

void main() {
  group('ShapePainter.shouldRepaint', () {
    test('repaints when a box is renamed (same count, same rect)', () {
      final old = painterFor([box(id: 'a', name: 'Old')]);
      final next = painterFor([box(id: 'a', name: 'New')]);

      // The latent bug: a length-only check would return false here because
      // the box count is unchanged — the rename would silently not show.
      expect(next.shouldRepaint(old), isTrue);
    });

    test('repaints when a box is resized', () {
      final old = painterFor([box(id: 'a', name: 'A', right: 100)]);
      final next = painterFor([box(id: 'a', name: 'A', right: 200)]);

      expect(next.shouldRepaint(old), isTrue);
    });

    test('repaints when a box is added', () {
      final old = painterFor([box(id: 'a', name: 'A')]);
      final next =
          painterFor([box(id: 'a', name: 'A'), box(id: 'b', name: 'B')]);

      expect(next.shouldRepaint(old), isTrue);
    });

    test('does not repaint when nothing visual changed', () {
      final old = painterFor([box(id: 'a', name: 'A')]);
      final next = painterFor([box(id: 'a', name: 'A')]);

      expect(next.shouldRepaint(old), isFalse);
    });

    test('does not repaint for the identical box list instance', () {
      final boxes = [box(id: 'a', name: 'A')];
      final old = painterFor(boxes);
      final next = painterFor(boxes);

      expect(next.shouldRepaint(old), isFalse);
    });
  });
}
