import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/models/navigation/page_data/page_data.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'push_page_action.freezed.dart';
part 'push_page_action.g.dart';

@freezed
abstract class PushPageAction with _$PushPageAction, ReduxAction {
  const PushPageAction._();

  factory PushPageAction({required PageData data}) = _PushPageAction;

  factory PushPageAction.fromJson(Map<String, dynamic> json) =>
      _$PushPageActionFromJson(json);
}
