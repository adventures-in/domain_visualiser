import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/models/problems/problem.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'remove_problem_action.freezed.dart';
part 'remove_problem_action.g.dart';

@freezed
abstract class RemoveProblemAction with _$RemoveProblemAction, ReduxAction {
  const RemoveProblemAction._();

  factory RemoveProblemAction({required Problem problem}) =
      _RemoveProblemAction;

  factory RemoveProblemAction.fromJson(Map<String, dynamic> json) =>
      _$RemoveProblemActionFromJson(json);
}
