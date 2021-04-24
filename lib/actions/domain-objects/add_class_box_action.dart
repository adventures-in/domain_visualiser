import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/models/domain-objects/domain_object.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'add_class_box_action.freezed.dart';
part 'add_class_box_action.g.dart';

@freezed
class AddClassBoxAction with _$AddClassBoxAction, ReduxAction {
  factory AddClassBoxAction(ClassBox classBox) = _AddClassBoxAction;

  factory AddClassBoxAction.fromJson(Map<String, dynamic> json) =>
      _$AddClassBoxActionFromJson(json);
}
