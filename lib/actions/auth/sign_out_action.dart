import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'sign_out_action.freezed.dart';
part 'sign_out_action.g.dart';

@freezed
class SignOutAction with _$SignOutAction, ReduxAction {
  factory SignOutAction() = _SignOutAction;

  factory SignOutAction.fromJson(Map<String, dynamic> json) =>
      _$SignOutActionFromJson(json);
}
