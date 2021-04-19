import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/models/profile/profile_data.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'store_profile_data_action.freezed.dart';
part 'store_profile_data_action.g.dart';

@freezed
class StoreProfileDataAction with _$StoreProfileDataAction, ReduxAction {
  @JsonSerializable(explicitToJson: true)
  factory StoreProfileDataAction({required ProfileData data}) =
      _StoreProfileDataAction;

  factory StoreProfileDataAction.fromJson(Map<String, dynamic> json) =>
      _$StoreProfileDataActionFromJson(json);
}
