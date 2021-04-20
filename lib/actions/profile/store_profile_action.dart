import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/models/profile/profile_data.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'store_profile_action.freezed.dart';
part 'store_profile_action.g.dart';

@freezed
class StoreProfileAction with _$StoreProfileAction, ReduxAction {
  @JsonSerializable(explicitToJson: true)
  factory StoreProfileAction(ProfileData data) = _StoreProfileDataAction;

  factory StoreProfileAction.fromJson(Map<String, dynamic> json) =>
      _$StoreProfileActionFromJson(json);
}
