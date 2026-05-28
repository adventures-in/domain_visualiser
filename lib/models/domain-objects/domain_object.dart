import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:domain_visualiser/converters/ilist_converters.dart';

part 'domain_object.freezed.dart';
part 'domain_object.g.dart';

@Freezed(unionKey: 'type', unionValueCase: FreezedUnionCase.pascal)
abstract class DomainObject with _$DomainObject {
  @FreezedUnionValue('SpecialCase')
  const factory DomainObject.classBox({
    /// Used for deserializing a [DomainObject] as the correct type.
    /// Leave as the default.
    @Default('ClassBox') String? type,

    /// The id of the ClassBox
    required String id,

    /// The round trip time
    int? flightTime,

    /// The id of the user that created the ClassBox
    String? userId,

    /// X,Y positions of the sides
    required double left,
    required double top,
    required double right,
    required double bottom,

    /// Metadata for the ClassBox
    String? name,
    @StringIListConverter() IList<String>? staticMethods,
    @StringIListConverter() IList<String>? instanceMethods,
    @StringIListConverter() IList<String>? staticVariables,
    @StringIListConverter() IList<String>? instanceVariables,
  }) = ClassBox;
  // const factory DomainObject.error(String message) = DomainObjectError;

  factory DomainObject.fromJson(Map<String, dynamic> json) =>
      _$DomainObjectFromJson(json);
}
