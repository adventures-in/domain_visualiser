import 'package:freezed_annotation/freezed_annotation.dart';

enum DatabaseSectionEnum {
  @JsonValue('PROFILE_DATA')
  profileData,
  @JsonValue('CLASS_BOXES')
  classBoxes,
}
