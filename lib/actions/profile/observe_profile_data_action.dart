import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'observe_profile_data_action.freezed.dart';
part 'observe_profile_data_action.g.dart';

@freezed
class ObserveProfileDataAction with _$ObserveProfileDataAction, ReduxAction {
  factory ObserveProfileDataAction() = _ObserveProfileDataAction;

  factory ObserveProfileDataAction.fromJson(Map<String, dynamic> json) =>
      _$ObserveProfileDataActionFromJson(json);
}
