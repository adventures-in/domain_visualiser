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
      painter: ShapePainter(_start, _end),
      child: Container(
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
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    canvas.drawRect(Rect.fromPoints(_start, _end), paint);
  }

  @override
  bool shouldRepaint(ShapePainter oldDelegate) {
    return _start != oldDelegate.start || _end != oldDelegate.end;
  }
}
