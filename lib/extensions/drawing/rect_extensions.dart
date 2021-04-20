import 'package:domain_visualiser/models/domain-objects/class_box.dart';
import 'package:flutter/painting.dart';

extension RectExtension on Rect {
  ClassBox toClassBox() =>
      ClassBox(left: left, top: top, right: right, bottom: bottom);
}
