import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'remove_current_page_action.freezed.dart';
part 'remove_current_page_action.g.dart';

@freezed
abstract class RemoveCurrentPageAction with _$RemoveCurrentPageAction, ReduxAction {
  const RemoveCurrentPageAction._();

  factory RemoveCurrentPageAction() = _RemoveCurrentPageAction;

  factory RemoveCurrentPageAction.fromJson(Map<String, dynamic> json) =>
      _$RemoveCurrentPageActionFromJson(json);
}
