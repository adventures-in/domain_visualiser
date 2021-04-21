import 'package:freezed_annotation/freezed_annotation.dart';

enum DatabaseSectionEnum {
  @JsonValue('PROFILE_DATA')
  profile,
  @JsonValue('CLASS_BOXES')
  classBoxes,
}
