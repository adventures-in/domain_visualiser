import 'package:domain_visualiser/models/class_box.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(AppWidget());
}

class AppWidget extends StatefulWidget {
  @override
  _AppWidgetState createState() => _AppWidgetState();
}

class _AppWidgetState extends State<AppWidget> {
  Offset _start = Offset.zero;
  ClassBox _creatingBox = ClassBox(Offset.zero, Offset.zero);
  final List<ClassBox> _boxes = [];

  final _linePaint = Paint()
    ..color = Colors.blue
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;

  final _fillPaint = Paint()..color = Colors.grey[100]!;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter:
          ShapePainter(_boxes, _creatingBox, _linePaint, _fillPaint),
      child: Container(
        color: Colors.white,
        child: GestureDetector(
          onTapUp: (details) => print('Tap: $details'),
          onPanStart: (details) {
            setState(() => _start = details.globalPosition);
          },
          onPanUpdate: (details) {
            setState(
                () => _creatingBox = ClassBox(_start, details.globalPosition));
          },
          onPanEnd: (details) => _boxes.add(_creatingBox),
        ),
      ),
    );
  }
}

class ShapePainter extends CustomPainter {
  final List<ClassBox> _boxes;
  final ClassBox? _creatingBox;
  final Paint _linePaint;
  final Paint _fillPaint;

  ShapePainter(List<ClassBox> boxes, ClassBox? creatingBox, Paint linePaint,
      Paint fillPaint)
      : _boxes = boxes,
        _creatingBox = creatingBox,
        _linePaint = linePaint,
        _fillPaint = fillPaint;

  ClassBox? get creatingBox => _creatingBox;

  @override
  void paint(Canvas canvas, Size size) {
    for (final box in _boxes) {
      drawClassBox(canvas, box);
    }

    if (_creatingBox != null) drawClassBox(canvas, _creatingBox!);
  }

  @override
  bool shouldRepaint(ShapePainter old) => _creatingBox != old.creatingBox;

  // Note: order is important
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
}
