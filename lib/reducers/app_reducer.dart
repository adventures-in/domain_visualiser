import 'package:codraw/models/app-state/app_state.dart';
import 'package:codraw/reducers/auth/sign_out.dart';
import 'package:codraw/reducers/auth/store_auth_step.dart';
import 'package:codraw/reducers/auth/store_auth_user_data.dart';
import 'package:codraw/reducers/domain-objects/store_class_boxes.dart';
import 'package:codraw/reducers/problems/add_problem.dart';
import 'package:codraw/reducers/problems/remove_problem.dart';
import 'package:codraw/reducers/profile/store_profile_data.dart';
import 'package:codraw/reducers/settings/update_settings.dart';
import 'package:redux/redux.dart';

/// Reducers specify how the application"s state changes in response to actions
/// sent to the store.
///
/// Each reducer returns a new [AppState].
final appReducer =
    combineReducers<AppState>(<AppState Function(AppState, dynamic)>[
  // Auth
  StoreAuthUserDataReducer(),
  StoreAuthStepReducer(),
  SignOutReducer(),
  // Domain Objects
  StoreClassBoxesReducer(),
  // Problems
  AddProblemReducer(),
  RemoveProblemReducer(),
  // Profile
  StoreProfileDataReducer(),
  // Settings
  UpdateSettingsReducer(),
]);
