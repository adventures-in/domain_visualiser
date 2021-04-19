// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$_ProfileData _$_$_ProfileDataFromJson(Map<String, dynamic> json) {
  return _$_ProfileData(
    id: json['id'] as String,
    displayName: json['displayName'] as String?,
    photoURL: json['photoURL'] as String?,
    firstName: json['firstName'] as String?,
    lastName: json['lastName'] as String?,
  );
}

Map<String, dynamic> _$_$_ProfileDataToJson(_$_ProfileData instance) =>
    <String, dynamic>{
      'id': instance.id,
      'displayName': instance.displayName,
      'photoURL': instance.photoURL,
      'firstName': instance.firstName,
      'lastName': instance.lastName,
    };
