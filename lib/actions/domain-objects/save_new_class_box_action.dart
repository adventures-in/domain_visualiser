import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/models/domain-objects/class_box.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'save_new_class_box_action.freezed.dart';
part 'save_new_class_box_action.g.dart';

@freezed
class SaveNewClassBoxAction with _$SaveNewClassBoxAction, ReduxAction {
  factory SaveNewClassBoxAction(ClassBox classBox) = _SaveNewClassBoxAction;

  factory SaveNewClassBoxAction.fromJson(Map<String, dynamic> json) =>
      _$SaveNewClassBoxActionFromJson(json);
}
