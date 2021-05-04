import 'package:domain_visualiser/actions/auth/store_auth_user_data_action.dart';
import 'package:domain_visualiser/actions/profile/store_profile_action.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/services/database_service.dart';
import 'package:redux/redux.dart';

/// When an auth state change event fires, if there is a user is signed in we
/// retrieve the profile data.
class StoreAuthUserDataMiddleware
    extends TypedMiddleware<AppState, StoreAuthUserDataAction> {
  StoreAuthUserDataMiddleware(DatabaseService databaseService)
      : super((store, action, next) async {
          next(action);

          /// If there is no signed in user, don't retrieve the profile data
          if (action.authUserData == null) return;

          final profile =
              await databaseService.retrieveProfile(action.authUserData!);
          store.dispatch(StoreProfileAction(profile));
        });
}
