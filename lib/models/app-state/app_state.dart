import 'package:domain_visualiser/enums/auth/auth_step_enum.dart';
import 'package:domain_visualiser/models/auth/auth_user_data.dart';
import 'package:domain_visualiser/models/domain-objects/domain_object.dart';
import 'package:domain_visualiser/models/navigation/page_data/page_data.dart';
import 'package:domain_visualiser/models/problems/problem.dart';
import 'package:domain_visualiser/models/profile/profile_data.dart';
import 'package:domain_visualiser/models/settings/settings.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_state.freezed.dart';
part 'app_state.g.dart';

@freezed
class AppState with _$AppState {
  @JsonSerializable(explicitToJson: true)
  factory AppState({
    /// Auth
    required AuthStepEnum authStep,
    AuthUserData? authUserData,

    /// Domain Objects
    required IList<ClassBox> classBoxes,

    /// Navigation
    required IList<PageData> pagesData,

    /// Problems
    required IList<Problem> problems,

    /// Profile
    ProfileData? profileData,

    /// Settings
    required Settings settings,
  }) = _AppState;

  factory AppState.fromJson(Map<String, dynamic> json) =>
      _$AppStateFromJson(json);

  factory AppState.init() => AppState(
      authStep: AuthStepEnum.checking,
      classBoxes: <ClassBox>[].lock,
      pagesData: <PageData>[InitialPageData()].lock,
      problems: IList(),
      settings: Settings.init());
}
