import 'package:domain_visualiser/middleware/app-init/plumb_streams.dart';
import 'package:domain_visualiser/middleware/auth/observe_auth_state.dart';
import 'package:domain_visualiser/middleware/auth/sign_in_with_apple.dart';
import 'package:domain_visualiser/middleware/auth/sign_in_with_google.dart';
import 'package:domain_visualiser/middleware/auth/sign_out.dart';
import 'package:domain_visualiser/middleware/domain-objects/add_class_box_middleware.dart';
import 'package:domain_visualiser/middleware/domain-objects/update_domain_middleware.dart';
import 'package:domain_visualiser/middleware/platform/detect_platform.dart';
import 'package:domain_visualiser/middleware/shared/connect_data_stream_middleware.dart';
import 'package:domain_visualiser/middleware/shared/disconnect_data_stream_middleware.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/services/auth_service.dart';
import 'package:domain_visualiser/services/database_service.dart';
import 'package:domain_visualiser/services/platform_service.dart';
import 'package:redux/redux.dart';

/// Middleware is used for a variety of things:
/// - Logging
/// - Async calls (database, network)
/// - Calling to system frameworks
///
/// These are performed when actions are dispatched to the Store
///
/// The output of an action can perform another action using the [NextDispatcher]
///
List<Middleware<AppState>> createAppMiddleware({
  required AuthService authService,
  required DatabaseService databaseService,
  required PlatformService platformService,
}) {
  return [
    // Auth
    ObserveAuthStateMiddleware(authService),
    PlumbStreamsMiddleware(authService, databaseService),
    SignInWithAppleMiddleware(authService),
    SignInWithGoogleMiddleware(authService),
    SignOutMiddleware(authService),
    // Domain Objects
    AddClassBoxMiddleware(databaseService, authService),
    UpdateDomainMiddleware(databaseService),
    // Platform
    DetectPlatformMiddleware(platformService),
    // Shared
    ConnectDataStreamMiddleware(databaseService),
    DisconnectDataStreamMiddleware(databaseService),
  ];
}
