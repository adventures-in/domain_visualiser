import 'package:domain_visualiser/enums/auth/auth_step_enum.dart';
import 'package:domain_visualiser/models/auth/auth_user_data.dart';
import 'package:domain_visualiser/models/domain-objects/domain_object.dart';
import 'package:domain_visualiser/models/navigation/page_data/page_data.dart';
import 'package:domain_visualiser/models/problems/problem.dart';
import 'package:domain_visualiser/models/profile/profile_data.dart';
import 'package:domain_visualiser/models/settings/settings.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:domain_visualiser/converters/ilist_converters.dart';

part 'app_state.freezed.dart';
part 'app_state.g.dart';

@freezed
abstract class AppState with _$AppState {
  factory AppState({
    /// Auth
    required AuthStepEnum authStep,
    AuthUserData? authUserData,

    /// Domain Objects
    @ClassBoxIListConverter() required IList<ClassBox> classBoxes,

    /// Navigation
    @PageDataIListConverter() required IList<PageData> pagesData,

    /// Problems
    @ProblemIListConverter() required IList<Problem> problems,

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
