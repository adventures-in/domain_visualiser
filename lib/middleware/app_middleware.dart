import 'package:domain_visualiser/middleware/app_init/plumb_streams.dart';
import 'package:domain_visualiser/middleware/auth/observe_auth_state.dart';
import 'package:domain_visualiser/middleware/auth/sign_in_with_apple.dart';
import 'package:domain_visualiser/middleware/auth/sign_in_with_google.dart';
import 'package:domain_visualiser/middleware/auth/sign_out.dart';
import 'package:domain_visualiser/middleware/platform/detect_platform.dart';
import 'package:domain_visualiser/middleware/shared/close_database_sink.dart';
import 'package:domain_visualiser/middleware/shared/open_database_sink.dart';
import 'package:domain_visualiser/models/app_state/app_state.dart';
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
    // Platform
    DetectPlatformMiddleware(platformService),
    // Shared
    CloseDatabaseSinkMiddleware(databaseService),
    OpenDatabaseSinkMiddleware(databaseService),
  ];
}
