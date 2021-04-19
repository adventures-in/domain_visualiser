// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connect_database_action.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$_ConnectDatabaseAction _$_$_ConnectDatabaseActionFromJson(
    Map<String, dynamic> json) {
  return _$_ConnectDatabaseAction(
    section: _$enumDecode(_$DatabaseSectionEnumEnumMap, json['section']),
  );
}

Map<String, dynamic> _$_$_ConnectDatabaseActionToJson(
        _$_ConnectDatabaseAction instance) =>
    <String, dynamic>{
      'section': _$DatabaseSectionEnumEnumMap[instance.section],
    };

K _$enumDecode<K, V>(
  Map<K, V> enumValues,
  Object? source, {
  K? unknownValue,
}) {
  if (source == null) {
    throw ArgumentError(
      'A value must be provided. Supported values: '
      '${enumValues.values.join(', ')}',
    );
  }

  return enumValues.entries.singleWhere(
    (e) => e.value == source,
    orElse: () {
      if (unknownValue == null) {
        throw ArgumentError(
          '`$source` is not one of the supported values: '
          '${enumValues.values.join(', ')}',
        );
      }
      return MapEntry(unknownValue, enumValues.values.first);
    },
  ).key;
}

const _$DatabaseSectionEnumEnumMap = {
  DatabaseSectionEnum.profileData: 'PROFILE_DATA',
  DatabaseSectionEnum.classBoxes: 'CLASS_BOXES',
};
