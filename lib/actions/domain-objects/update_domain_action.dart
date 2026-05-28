import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/models/domain-objects/domain_object.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'update_domain_action.freezed.dart';
part 'update_domain_action.g.dart';

@freezed
abstract class UpdateDomainAction with _$UpdateDomainAction, ReduxAction {
  const UpdateDomainAction._();

  factory UpdateDomainAction(DomainObject object) = _UpdateDomainAction;

  factory UpdateDomainAction.fromJson(Map<String, dynamic> json) =>
      _$UpdateDomainActionFromJson(json);
}
