import 'package:domain_visualiser/enums/platform/platform_enum.dart';
import 'package:domain_visualiser/services/wrappers/platform_wrapper.dart';
import 'package:domain_visualiser/services/wrappers/url_launcher_wrapper.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class PlatformService {
  PlatformService(
      {PlatformWrapper? platformWrapper,
      UrlLauncherWrapper? urlLauncherWrapper})
      : _platformWrapper = platformWrapper ?? PlatformWrapper();

  final PlatformWrapper _platformWrapper;

  PlatformEnum detectPlatform() {
    if (kIsWeb) {
      return PlatformEnum.web;
    }
    if (_platformWrapper.isMacOS) {
      return PlatformEnum.macOS;
    }
    if (_platformWrapper.isFuchsia) {
      return PlatformEnum.fuchsia;
    }
    if (_platformWrapper.isLinux) {
      return PlatformEnum.linux;
    }
    if (_platformWrapper.isWindows) {
      return PlatformEnum.windows;
    }
    if (_platformWrapper.isIOS) {
      return PlatformEnum.iOS;
    }
    if (_platformWrapper.isAndroid) {
      return PlatformEnum.android;
    }
    return PlatformEnum.unknown;
  }
}
