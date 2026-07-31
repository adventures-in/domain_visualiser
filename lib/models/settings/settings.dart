import 'package:codraw/enums/platform/platform_enum.dart';
import 'package:codraw/enums/settings/brightness_mode_enum.dart';
import 'package:codraw/enums/settings/theme_brightness_enum.dart';
import 'package:codraw/models/settings/theme_colors.dart';
import 'package:codraw/models/settings/theme_set.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings.freezed.dart';
part 'settings.g.dart';

@freezed
abstract class Settings with _$Settings {
  factory Settings({
    required ThemeSet darkTheme,
    required ThemeSet lightTheme,
    required BrightnessModeEnum brightnessMode,
    required PlatformEnum platform,
  }) = _Settings;

  factory Settings.fromJson(Map<String, dynamic> json) =>
      _$SettingsFromJson(json);

  factory Settings.init() => Settings(
      darkTheme: ThemeSet(
          brightness: ThemeBrightnessEnum.dark, colors: ThemeColors.standard),
      lightTheme: ThemeSet(
          brightness: ThemeBrightnessEnum.light, colors: ThemeColors.standard),
      brightnessMode: BrightnessModeEnum.light,
      platform: PlatformEnum.unknown);
}
