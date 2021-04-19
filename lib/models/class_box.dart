import 'package:flutter/painting.dart';

class ClassBox {
  ClassBox(Rect rect) : _rect = rect;
  final Rect _rect;
  final String _name = '';
  final List<String> _staticMethods = [];
  final List<String> _instanceMethods = [];
  final List<String> _staticVariables = [];
  final List<String> _instanceVariables = [];

  ClassBox.fromPoints(Offset start, Offset end)
      : _rect = Rect.fromPoints(start, end);

  Rect get rect => _rect;
  String get name => _name;
  List<String> get staticMethods => _staticMethods;
  List<String> get instanceMethods => _instanceMethods;
  List<String> get staticVariables => _staticVariables;
  List<String> get instanceVariables => _instanceVariables;
}
