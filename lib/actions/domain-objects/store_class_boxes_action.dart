import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/models/domain-objects/domain_object.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'store_class_boxes_action.freezed.dart';
part 'store_class_boxes_action.g.dart';

@freezed
class StoreClassBoxesAction with _$StoreClassBoxesAction, ReduxAction {
  factory StoreClassBoxesAction(IList<ClassBox> boxes) = _StoreClassBoxesAction;

  factory StoreClassBoxesAction.fromJson(Map<String, dynamic> json) =>
      _$StoreClassBoxesActionFromJson(json);
}
