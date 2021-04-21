import 'package:domain_visualiser/actions/auth/sign_in_with_apple_action.dart';
import 'package:domain_visualiser/actions/auth/sign_in_with_google_action.dart';
import 'package:domain_visualiser/enums/platform/platform_enum.dart';
import 'package:domain_visualiser/extensions/flutter/context_extensions.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/widgets/auth/auth_page_buttons/apple_sign_in_button.dart';
import 'package:domain_visualiser/widgets/auth/auth_page_buttons/google_sign_in_button.dart';
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
