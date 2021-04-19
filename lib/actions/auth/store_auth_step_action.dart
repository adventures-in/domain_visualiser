import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/enums/auth/auth_step_enum.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'store_auth_step_action.freezed.dart';
part 'store_auth_step_action.g.dart';

@freezed
class StoreAuthStepAction with _$StoreAuthStepAction, ReduxAction {
  factory StoreAuthStepAction({required AuthStepEnum step}) =
      _StoreAuthStepAction;

  factory StoreAuthStepAction.fromJson(Map<String, dynamic> json) =>
      _$StoreAuthStepActionFromJson(json);
}
