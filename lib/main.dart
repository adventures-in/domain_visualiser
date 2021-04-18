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
  Rect _creatingRect = Rect.fromPoints(Offset.zero, Offset.zero);
  final List<Rect> _rects = [];

  final _linePaint = Paint()
    ..color = Colors.blue
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;

  final _fillPaint = Paint()..color = Colors.grey[100]!;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter:
          ShapePainter(_rects, _creatingRect, _linePaint, _fillPaint),
      child: Container(
        color: Colors.white,
        child: GestureDetector(
          onTapUp: (details) => print('Tap: $details'),
          onPanStart: (details) {
            setState(() => _start = details.globalPosition);
          },
          onPanUpdate: (details) {
            setState(() => _creatingRect =
                Rect.fromPoints(_start, details.globalPosition));
          },
          onPanEnd: (details) => _rects.add(_creatingRect),
        ),
      ),
    );
  }
}

class ShapePainter extends CustomPainter {
  final List<Rect> _rects;
  final Rect? _creatingRect;
  final Paint _linePaint;
  final Paint _fillPaint;

  ShapePainter(
      List<Rect> rects, Rect? creatingRect, Paint linePaint, Paint fillPaint)
      : _rects = rects,
        _creatingRect = creatingRect,
        _linePaint = linePaint,
        _fillPaint = fillPaint;

  Rect? get creatingRect => _creatingRect;

  @override
  void paint(Canvas canvas, Size size) {
    for (final rect in _rects) {
      drawClassBox(canvas, rect);
    }

    if (_creatingRect != null) drawClassBox(canvas, _creatingRect!);
  }

  @override
  bool shouldRepaint(ShapePainter old) => _creatingRect != old.creatingRect;

  void drawClassBox(Canvas canvas, Rect rect) {
    final path = Path()..addRect(rect);

    canvas.drawShadow(path.shift(Offset(2, 2)), Colors.black, 1.0, true);
    canvas.drawPath(path, _fillPaint);

    canvas.drawLine(rect.bottomLeft, rect.bottomRight, _linePaint);
    canvas.drawLine(rect.bottomRight, rect.topRight, _linePaint);
    canvas.drawLine(rect.topRight, rect.topLeft, _linePaint);
    canvas.drawLine(rect.topLeft, rect.bottomLeft, _linePaint);
  }
}
