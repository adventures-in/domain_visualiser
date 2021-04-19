// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'problem.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$_Problem _$_$_ProblemFromJson(Map<String, dynamic> json) {
  return _$_Problem(
    errorString: json['errorString'] as String,
    traceString: json['traceString'] as String?,
    info: (json['info'] as Map<String, dynamic>?)?.map(
      (k, e) => MapEntry(k, e as Object),
    ),
  );
}

Map<String, dynamic> _$_$_ProblemToJson(_$_Problem instance) =>
    <String, dynamic>{
      'errorString': instance.errorString,
      'traceString': instance.traceString,
      'info': instance.info,
    };
