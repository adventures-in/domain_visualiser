// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'add_problem_action.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$_AddProblemAction _$_$_AddProblemActionFromJson(Map<String, dynamic> json) {
  return _$_AddProblemAction(
    errorString: json['errorString'] as String,
    traceString: json['traceString'] as String?,
    info: (json['info'] as Map<String, dynamic>?)?.map(
      (k, e) => MapEntry(k, e as Object),
    ),
  );
}

Map<String, dynamic> _$_$_AddProblemActionToJson(
        _$_AddProblemAction instance) =>
    <String, dynamic>{
      'errorString': instance.errorString,
      'traceString': instance.traceString,
      'info': instance.info,
    };
