import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/enums/platform/platform_enum.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'update_settings_action.freezed.dart';
part 'update_settings_action.g.dart';

@freezed
class UpdateSettingsAction with _$UpdateSettingsAction, ReduxAction {
  factory UpdateSettingsAction({required PlatformEnum platform}) =
      _UpdateSettingsAction;

  factory UpdateSettingsAction.fromJson(Map<String, dynamic> json) =>
      _$UpdateSettingsActionFromJson(json);
}
