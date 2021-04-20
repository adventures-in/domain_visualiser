import 'package:domain_visualiser/enums/database/database_section_enum.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'database_section.freezed.dart';
part 'database_section.g.dart';

@freezed
class DatabaseSection with _$DatabaseSection {
  factory DatabaseSection(
      {required DatabaseSectionEnum id,
      required String location}) = _DatabaseSection;

  factory DatabaseSection.fromJson(Map<String, dynamic> json) =>
      _$DatabaseSectionFromJson(json);
}
