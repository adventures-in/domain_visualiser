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
  Rect _currentRect = Rect.fromPoints(Offset.zero, Offset.zero);

  final _linePaint = Paint()
    ..color = Colors.blue
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;

  final _fillPaint = Paint()..color = Colors.grey[100]!;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: ShapePainter(_currentRect, _linePaint, _fillPaint),
      child: Container(
        color: Colors.white,
        child: GestureDetector(
          onPanStart: (details) {
            setState(() => _start = details.globalPosition);
          },
          onPanUpdate: (details) {
            setState(() =>
                _currentRect = Rect.fromPoints(_start, details.globalPosition));
          },
        ),
      ),
    );
  }
}

class ShapePainter extends CustomPainter {
  final Rect _rect;
  final Paint _linePaint;
  final Paint _fillPaint;

  ShapePainter(Rect rect, Paint linePaint, Paint fillPaint)
      : _rect = rect,
        _linePaint = linePaint,
        _fillPaint = fillPaint;

  Rect get rect => _rect;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRect(_rect);

    canvas.drawShadow(path.shift(Offset(2, 2)), Colors.black, 1.0, true);
    canvas.drawPath(path, _fillPaint);

    canvas.drawLine(_rect.bottomLeft, _rect.bottomRight, _linePaint);
    canvas.drawLine(_rect.bottomRight, _rect.topRight, _linePaint);
    canvas.drawLine(_rect.topRight, _rect.topLeft, _linePaint);
    canvas.drawLine(_rect.topLeft, _rect.bottomLeft, _linePaint);
  }

  @override
  bool shouldRepaint(ShapePainter old) => _rect != old.rect;
}
