import 'package:codraw/enums/settings/theme_brightness_enum.dart';
import 'package:codraw/models/settings/theme_colors.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'theme_set.freezed.dart';
part 'theme_set.g.dart';

@freezed
abstract class ThemeSet with _$ThemeSet {
  factory ThemeSet({
    required ThemeColors colors,
    required ThemeBrightnessEnum brightness,
  }) = _ThemeSet;

  factory ThemeSet.fromJson(Map<String, dynamic> json) =>
      _$ThemeSetFromJson(json);
}
