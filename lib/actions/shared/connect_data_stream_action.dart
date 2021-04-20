import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/models/shared/database_section.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'connect_data_stream_action.freezed.dart';
part 'connect_data_stream_action.g.dart';

@freezed
class ConnectDataStreamAction with _$ConnectDataStreamAction, ReduxAction {
  factory ConnectDataStreamAction({required DatabaseSection section}) =
      _ConnectDatabaseAction;

  factory ConnectDataStreamAction.fromJson(Map<String, dynamic> json) =>
      _$ConnectDataStreamActionFromJson(json);
}
