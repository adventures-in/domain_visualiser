import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/enums/database/database_section_enum.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'connect_database_action.freezed.dart';
part 'connect_database_action.g.dart';

@freezed
class ConnectDatabaseAction with _$ConnectDatabaseAction, ReduxAction {
  factory ConnectDatabaseAction({required DatabaseSectionEnum section}) =
      _ConnectDatabaseAction;

  factory ConnectDatabaseAction.fromJson(Map<String, dynamic> json) =>
      _$ConnectDatabaseActionFromJson(json);
}
