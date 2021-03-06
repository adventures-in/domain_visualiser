import 'package:domain_visualiser/enums/platform/platform_enum.dart';
import 'package:domain_visualiser/enums/settings/brightness_mode_enum.dart';
import 'package:domain_visualiser/enums/settings/theme_brightness_enum.dart';
import 'package:domain_visualiser/models/settings/theme_colors.dart';
import 'package:domain_visualiser/models/settings/theme_set.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings.freezed.dart';
part 'settings.g.dart';

@freezed
class Settings with _$Settings {
  @JsonSerializable(explicitToJson: true)
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
