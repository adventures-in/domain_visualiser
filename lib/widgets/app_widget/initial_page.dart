import 'package:domain_visualiser/enums/auth/auth_step_enum.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/models/auth/auth_user_data.dart';
import 'package:domain_visualiser/widgets/auth/auth_page.dart';
import 'package:domain_visualiser/widgets/drawing_page.dart';
import 'package:domain_visualiser/widgets/shared/waiting_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class InitialPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AuthStepEnum>(
        distinct: true,
        converter: (store) => store.state.authStep,
        builder: (context, authStep) {
          switch (authStep) {
            case AuthStepEnum.checking:
              return WaitingIndicator('Checking where we\'re at...');
            case AuthStepEnum.contactingApple:
              return WaitingIndicator('Contacting Apple...');
            case AuthStepEnum.contactingGoogle:
              return WaitingIndicator('Contacting Google...');
            case AuthStepEnum.signingInWithFirebase:
              return WaitingIndicator('Sharpening the 4B...');
            case AuthStepEnum.waitingForInput:
              return StoreConnector<AppState, AuthUserData?>(
                  distinct: true,
                  converter: (store) => store.state.authUserData,
                  builder: (context, userData) =>
                      (userData == null) ? AuthPage() : DrawingPage());
            default:
              return Container();
          }
        });
  }
}
