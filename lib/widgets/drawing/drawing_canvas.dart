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
      _creatingRect != old.creatingRect || _boxes.length != old.boxes.length;

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
  }

  void drawCreatingRect(Canvas canvas, Rect rect) {
    // draw edges
    canvas.drawLine(rect.bottomLeft, rect.bottomRight, _linePaint);
    canvas.drawLine(rect.bottomRight, rect.topRight, _linePaint);
    canvas.drawLine(rect.topRight, rect.topLeft, _linePaint);
    canvas.drawLine(rect.topLeft, rect.bottomLeft, _linePaint);
  }
}
