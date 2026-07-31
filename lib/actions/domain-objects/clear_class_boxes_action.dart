import 'package:codraw/actions/redux_action.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'clear_class_boxes_action.freezed.dart';
part 'clear_class_boxes_action.g.dart';

/// Dispatched by the canvas "clear" control. Tombstones every currently-visible
/// [ClassBox] via [ClearClassBoxesMiddleware]; carries no payload.
@freezed
abstract class ClearClassBoxesAction
    with _$ClearClassBoxesAction, ReduxAction {
  const ClearClassBoxesAction._();

  factory ClearClassBoxesAction() = _ClearClassBoxesAction;

  factory ClearClassBoxesAction.fromJson(Map<String, dynamic> json) =>
      _$ClearClassBoxesActionFromJson(json);
}
