import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'class_box.freezed.dart';
part 'class_box.g.dart';

@freezed
class ClassBox with _$ClassBox {
  factory ClassBox(
      {required double left,
      required double top,
      required double right,
      required double bottom,
      String? name,
      IList<String>? staticMethods,
      IList<String>? instanceMethods,
      IList<String>? staticVariables,
      IList<String>? instanceVariables}) = _ClassBox;

  factory ClassBox.fromJson(Map<String, dynamic> json) =>
      _$ClassBoxFromJson(json);
}
