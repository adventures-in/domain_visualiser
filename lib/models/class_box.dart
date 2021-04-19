import 'package:flutter/painting.dart';

class ClassBox {
  ClassBox(Offset start, Offset end) : _rect = Rect.fromPoints(start, end);
  final Rect _rect;

  Rect get rect => _rect;
}
