import 'package:codraw/middleware/app-init/plumb_streams.dart';
import 'package:codraw/middleware/auth/observe_auth_state.dart';
import 'package:codraw/middleware/auth/sign_in_with_apple.dart';
import 'package:codraw/middleware/auth/sign_in_with_google.dart';
import 'package:codraw/middleware/auth/sign_out.dart';
import 'package:codraw/middleware/domain-objects/add_class_box_middleware.dart';
import 'package:codraw/middleware/domain-objects/clear_class_boxes_middleware.dart';
import 'package:codraw/middleware/domain-objects/update_domain_middleware.dart';
import 'package:codraw/middleware/platform/detect_platform.dart';
import 'package:codraw/middleware/shared/connect_data_stream_middleware.dart';
import 'package:codraw/middleware/shared/disconnect_data_stream_middleware.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:codraw/services/auth_service.dart';
import 'package:codraw/services/platform_service.dart';
import 'package:codraw/sync/graph_sync_backend.dart';
import 'package:codraw/graph/hlc_manager.dart';
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
  required GraphSyncBackend backend,
  required PlatformService platformService,
  required HlcManager hlc,
  required String originClientId,
}) {
  return [
    // Auth
    ObserveAuthStateMiddleware(authService),
    PlumbStreamsMiddleware(authService, backend),
    SignInWithAppleMiddleware(authService),
    SignInWithGoogleMiddleware(authService),
    SignOutMiddleware(authService),
    // Domain Objects
    AddClassBoxMiddleware(backend, authService, hlc, originClientId),
    ClearClassBoxesMiddleware(backend, hlc, originClientId),
    UpdateDomainMiddleware(backend, hlc, originClientId),
    // Platform
    DetectPlatformMiddleware(platformService),
    // Shared
    ConnectDataStreamMiddleware(backend),
    DisconnectDataStreamMiddleware(backend),
  ];
}
