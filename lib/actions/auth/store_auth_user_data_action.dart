import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/models/auth/auth_user_data.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'store_auth_user_data_action.freezed.dart';
part 'store_auth_user_data_action.g.dart';

@freezed
class StoreAuthUserDataAction with _$StoreAuthUserDataAction, ReduxAction {
  @JsonSerializable(explicitToJson: true)
  factory StoreAuthUserDataAction({AuthUserData? authUserData}) =
      _StoreAuthUserDataAction;

  factory StoreAuthUserDataAction.fromJson(Map<String, dynamic> json) =>
      _$StoreAuthUserDataActionFromJson(json);
}
