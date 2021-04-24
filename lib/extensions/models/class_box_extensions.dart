import 'package:domain_visualiser/models/domain-objects/domain_object.dart';
import 'package:flutter/painting.dart';

extension ClassBoxExtension on ClassBox {
  Rect get rect => Rect.fromLTRB(left, top, right, bottom);
}
