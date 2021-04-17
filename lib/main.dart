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
  Offset _end = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: ShapePainter(_start, _end),
      child: Container(
        color: Colors.white,
        child: GestureDetector(
          onPanStart: (details) {
            setState(() {
              _start = details.globalPosition;
              _end = details.globalPosition;
            });
          },
          onPanUpdate: (details) {
            setState(() => _end = details.globalPosition);
          },
        ),
      ),
    );
  }
}

class ShapePainter extends CustomPainter {
  final Offset _start;
  final Offset _end;

  ShapePainter(Offset start, Offset end)
      : _start = start,
        _end = end;

  Offset get start => _start;
  Offset get end => _end;

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = Colors.teal
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromPoints(_start, _end);
    final path = Path()..addRect(rect);

    canvas.drawShadow(path.shift(Offset(2, 2)), Colors.black, 2.0, true);
    canvas.drawPath(path, Paint()..color = Colors.white);

    canvas.drawLine(rect.bottomLeft, rect.bottomRight, paint);
    canvas.drawLine(rect.bottomRight, rect.topRight, paint);
    canvas.drawLine(rect.topRight, rect.topLeft, paint);
    canvas.drawLine(rect.topLeft, rect.bottomLeft, paint);
  }

  @override
  bool shouldRepaint(ShapePainter oldDelegate) {
    return _start != oldDelegate.start || _end != oldDelegate.end;
  }
}
