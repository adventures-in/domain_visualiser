import 'package:domain_visualiser/enums/settings/brightness_mode_enum.dart';
import 'package:domain_visualiser/enums/settings/theme_brightness_enum.dart';
import 'package:domain_visualiser/models/settings/theme_set.dart';
import 'package:flutter/material.dart';

// Static functions must be called on the extension name, ie. NewThemeData
// The naming choice here (ie. MakeThemeData) results in MakeThemeData.from(...)
// which is not bad in this context but may not work in others
extension MakeThemeData on ThemeData {
  static ThemeData from(ThemeSet themeSet) {
    if (themeSet.brightness == ThemeBrightnessEnum.light) {
      return ThemeData.from(
          colorScheme: ColorScheme.light(
              primary: Color(themeSet.colors.primary),
              secondary: Color(themeSet.colors.secondary),
              error: Color(themeSet.colors.error)));
    } else {
      return ThemeData.from(
          colorScheme: ColorScheme.dark(
              primary: Color(themeSet.colors.primary),
              secondary: Color(themeSet.colors.secondary),
              error: Color(themeSet.colors.error)));
    }
  }
}

extension MakeThemeMode on ThemeMode {
  static ThemeMode from(BrightnessModeEnum brightness) {
    return (brightness == BrightnessModeEnum.light)
        ? ThemeMode.light
        : (brightness == BrightnessModeEnum.dark)
            ? ThemeMode.dark
            : ThemeMode.system;
  }
}
