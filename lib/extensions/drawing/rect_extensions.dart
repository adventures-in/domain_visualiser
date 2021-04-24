import 'package:domain_visualiser/models/domain-objects/domain_object.dart';
import 'package:flutter/painting.dart';
import 'package:uuid/uuid.dart';

extension RectExtension on Rect {
  ClassBox toClassBox() => ClassBox(
      id: Uuid().v1(), left: left, top: top, right: right, bottom: bottom);
}
