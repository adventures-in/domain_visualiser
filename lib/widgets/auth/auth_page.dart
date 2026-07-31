import 'package:codraw/actions/auth/sign_in_with_apple_action.dart';
import 'package:codraw/actions/auth/sign_in_with_google_action.dart';
import 'package:codraw/enums/platform/platform_enum.dart';
import 'package:codraw/extensions/flutter/context_extensions.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:codraw/widgets/auth/auth_page_buttons/apple_sign_in_button.dart';
import 'package:codraw/widgets/auth/auth_page_buttons/google_sign_in_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class AuthPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
        child: StoreConnector<AppState, PlatformEnum>(
            distinct: true,
            converter: (store) => store.state.settings.platform,
            builder: (context, platform) {
              return (platform == PlatformEnum.macOS ||
                      platform == PlatformEnum.iOS)
                  ? AppleSignInButton(
                      style: AppleButtonStyle.black,
                      onPressed: () =>
                          context.dispatch(SignInWithAppleAction()))
                  : GoogleSignInButton(
                      onPressed: () =>
                          context.dispatch(SignInWithGoogleAction()));
            }));
  }
}
