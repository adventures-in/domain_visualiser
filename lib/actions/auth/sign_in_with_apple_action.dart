import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'sign_in_with_apple_action.freezed.dart';
part 'sign_in_with_apple_action.g.dart';

@freezed
class SignInWithAppleAction with _$SignInWithAppleAction, ReduxAction {
  factory SignInWithAppleAction() = _SignInWithAppleAction;

  factory SignInWithAppleAction.fromJson(Map<String, dynamic> json) =>
      _$SignInWithAppleActionFromJson(json);
}
