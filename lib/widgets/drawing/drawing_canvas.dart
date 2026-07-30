import 'package:domain_visualiser/actions/domain-objects/add_class_box_action.dart';
import 'package:domain_visualiser/actions/domain-objects/update_domain_action.dart';
import 'package:domain_visualiser/extensions/drawing/rect_extensions.dart';
import 'package:domain_visualiser/extensions/extensions.dart';
import 'package:domain_visualiser/extensions/flutter/context_extensions.dart';
import 'package:domain_visualiser/models/domain-objects/domain_object.dart';
import 'package:flutter/material.dart';

class DrawingCanvas extends StatefulWidget {
  DrawingCanvas(this.boxes);

  final List<ClassBox> boxes;

  @override
  _DrawingCanvasState createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  Offset _start = Offset.zero;
  Rect? _creatingRect;
  ClassBox? _selectedClassBox;
  final Map<String, int> _departureTimeOf = {};

  final _linePaint = Paint()
    ..color = Colors.blue
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;

  final _fillPaint = Paint()..color = Colors.grey[100]!;

  @override
  void didUpdateWidget(covariant DrawingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (var box in widget.boxes) {
      final departureTime = _departureTimeOf[box.id];
      if (departureTime != null) {
        _departureTimeOf.remove(box.id);

        context.dispatch(UpdateDomainAction(box.copyWith(
            flightTime:
                DateTime.now().millisecondsSinceEpoch - departureTime)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: ShapePainter(widget.boxes, _selectedClassBox,
          _creatingRect, _linePaint, _fillPaint),
      child: Container(
        color: Colors.white,
        child: GestureDetector(
            onTapUp: (details) => print('Tap: ${details.localPosition}'),
            onPanStart: (details) {
              setState(() => _start = details.localPosition);
            },
            onPanUpdate: (details) {
              setState(() => _creatingRect =
                  Rect.fromPoints(_start, details.localPosition));
            },
            onPanEnd: (details) {
              // dispatch action to save class box
              final newClassBox = _creatingRect!.toClassBox();
              _departureTimeOf[newClassBox.id] =
                  DateTime.now().millisecondsSinceEpoch;
              context.dispatch(AddClassBoxAction(newClassBox));
              _selectedClassBox = newClassBox;
              _creatingRect = null;
            }),
      ),
    );
  }
}

class ShapePainter extends CustomPainter {
  final List<ClassBox> _boxes;
  final ClassBox? _selectedClassBox;
  final Rect? _creatingRect;
  final Paint _linePaint;
  final Paint _fillPaint;

  ShapePainter(List<ClassBox> boxes, ClassBox? selectedClassBox,
      Rect? creatingRect, Paint linePaint, Paint fillPaint)
      : _boxes = boxes,
        _selectedClassBox = selectedClassBox,
        _creatingRect = creatingRect,
        _linePaint = linePaint,
        _fillPaint = fillPaint;

  Rect? get creatingRect => _creatingRect;
  List<ClassBox> get boxes => _boxes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final box in _boxes) {
      drawClassBox(canvas, box);
    }

    if (_selectedClassBox != null) {
      drawSelectedClassBox(canvas, _selectedClassBox!);
    }

    if (_creatingRect != null) drawCreatingRect(canvas, _creatingRect!);
  }

  @override
  bool shouldRepaint(ShapePainter old) =>
      _creatingRect != old._creatingRect ||
      _selectedClassBox != old._selectedClassBox ||
      !_boxesVisuallyEqual(_boxes, old._boxes);

  /// Cheap visual-equality check over the fields the painter actually draws:
  /// position (rect) and [ClassBox.name]. A rename changes the name without
  /// changing box count, so a length-only check would miss it and the label
  /// would silently not repaint — this is on the agent-as-peer live-edit path.
  static bool _boxesVisuallyEqual(List<ClassBox> a, List<ClassBox> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.name != y.name ||
          x.left != y.left ||
          x.top != y.top ||
          x.right != y.right ||
          x.bottom != y.bottom) {
        return false;
      }
    }
    return true;
  }

  void drawClassBox(Canvas canvas, ClassBox box) {
    final rect = box.rect;
    final path = Path()..addRect(rect);

    // draw shadow and fill
    canvas.drawShadow(path.shift(Offset(2, 2)), Colors.black, 1.0, true);
    canvas.drawPath(path, _fillPaint);

    // draw edges
    canvas.drawLine(rect.bottomLeft, rect.bottomRight, _linePaint);
    canvas.drawLine(rect.bottomRight, rect.topRight, _linePaint);
    canvas.drawLine(rect.topRight, rect.topLeft, _linePaint);
    canvas.drawLine(rect.topLeft, rect.bottomLeft, _linePaint);

    // draw line in the middle
    canvas.drawLine(rect.topLeft, rect.bottomLeft, _linePaint);

    drawClassName(canvas, rect, box.name);
  }

  void drawSelectedClassBox(Canvas canvas, ClassBox box) {
    final rect = box.rect;
    final path = Path()..addRect(rect);

    // draw shadow and fill
    canvas.drawShadow(path.shift(Offset(2, 2)), Colors.black, 1.0, true);
    canvas.drawPath(path, _fillPaint);

    // draw edges
    canvas.drawLine(rect.bottomLeft, rect.bottomRight, _linePaint);
    canvas.drawLine(rect.bottomRight, rect.topRight, _linePaint);
    canvas.drawLine(rect.topRight, rect.topLeft, _linePaint);
    canvas.drawLine(rect.topLeft, rect.bottomLeft, _linePaint);

    // draw line in the middle
    canvas.drawLine(rect.topLeft, rect.bottomLeft, _linePaint);

    drawClassName(canvas, rect, box.name);
  }

  void drawCreatingRect(Canvas canvas, Rect rect) {
    // draw edges
    canvas.drawLine(rect.bottomLeft, rect.bottomRight, _linePaint);
    canvas.drawLine(rect.bottomRight, rect.topRight, _linePaint);
    canvas.drawLine(rect.topRight, rect.topLeft, _linePaint);
    canvas.drawLine(rect.topLeft, rect.bottomLeft, _linePaint);
  }

  /// Renders the class [name] in the top area of [rect], dark and bold on the
  /// light fill. Clipped to [rect] so text never spills past the box or off
  /// canvas (boxes can be dragged to any size, incl. very thin/small), with an
  /// ellipsis on overflow. No-op for a null/empty name or a degenerate rect.
  void drawClassName(Canvas canvas, Rect rect, String? name) {
    if (name == null || name.isEmpty) return;

    const padding = 6.0;
    final maxWidth = rect.width - padding * 2;
    final maxHeight = rect.height - padding * 2;
    if (maxWidth <= 0 || maxHeight <= 0) return;

    final textPainter = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          color: Colors.grey[900],
          fontSize: 14,
          fontWeight: FontWeight.bold,
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);

    // Clip to the box so an oversized label (or a tiny box) can never draw
    // outside its own rect.
    canvas.save();
    canvas.clipRect(rect);
    textPainter.paint(canvas, rect.topLeft + const Offset(padding, padding));
    canvas.restore();
  }
}
