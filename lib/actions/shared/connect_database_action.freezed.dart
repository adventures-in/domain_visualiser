// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides

part of 'connect_database_action.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more informations: https://github.com/rrousselGit/freezed#custom-getters-and-methods');

ConnectDatabaseAction _$ConnectDatabaseActionFromJson(
    Map<String, dynamic> json) {
  return _ConnectDatabaseAction.fromJson(json);
}

/// @nodoc
class _$ConnectDatabaseActionTearOff {
  const _$ConnectDatabaseActionTearOff();

  _ConnectDatabaseAction call({required DatabaseSectionEnum section}) {
    return _ConnectDatabaseAction(
      section: section,
    );
  }

  ConnectDatabaseAction fromJson(Map<String, Object> json) {
    return ConnectDatabaseAction.fromJson(json);
  }
}

/// @nodoc
const $ConnectDatabaseAction = _$ConnectDatabaseActionTearOff();

/// @nodoc
mixin _$ConnectDatabaseAction {
  DatabaseSectionEnum get section => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ConnectDatabaseActionCopyWith<ConnectDatabaseAction> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ConnectDatabaseActionCopyWith<$Res> {
  factory $ConnectDatabaseActionCopyWith(ConnectDatabaseAction value,
          $Res Function(ConnectDatabaseAction) then) =
      _$ConnectDatabaseActionCopyWithImpl<$Res>;
  $Res call({DatabaseSectionEnum section});
}

/// @nodoc
class _$ConnectDatabaseActionCopyWithImpl<$Res>
    implements $ConnectDatabaseActionCopyWith<$Res> {
  _$ConnectDatabaseActionCopyWithImpl(this._value, this._then);

  final ConnectDatabaseAction _value;
  // ignore: unused_field
  final $Res Function(ConnectDatabaseAction) _then;

  @override
  $Res call({
    Object? section = freezed,
  }) {
    return _then(_value.copyWith(
      section: section == freezed
          ? _value.section
          : section // ignore: cast_nullable_to_non_nullable
              as DatabaseSectionEnum,
    ));
  }
}

/// @nodoc
abstract class _$ConnectDatabaseActionCopyWith<$Res>
    implements $ConnectDatabaseActionCopyWith<$Res> {
  factory _$ConnectDatabaseActionCopyWith(_ConnectDatabaseAction value,
          $Res Function(_ConnectDatabaseAction) then) =
      __$ConnectDatabaseActionCopyWithImpl<$Res>;
  @override
  $Res call({DatabaseSectionEnum section});
}

/// @nodoc
class __$ConnectDatabaseActionCopyWithImpl<$Res>
    extends _$ConnectDatabaseActionCopyWithImpl<$Res>
    implements _$ConnectDatabaseActionCopyWith<$Res> {
  __$ConnectDatabaseActionCopyWithImpl(_ConnectDatabaseAction _value,
      $Res Function(_ConnectDatabaseAction) _then)
      : super(_value, (v) => _then(v as _ConnectDatabaseAction));

  @override
  _ConnectDatabaseAction get _value => super._value as _ConnectDatabaseAction;

  @override
  $Res call({
    Object? section = freezed,
  }) {
    return _then(_ConnectDatabaseAction(
      section: section == freezed
          ? _value.section
          : section // ignore: cast_nullable_to_non_nullable
              as DatabaseSectionEnum,
    ));
  }
}

@JsonSerializable()

/// @nodoc
class _$_ConnectDatabaseAction implements _ConnectDatabaseAction {
  _$_ConnectDatabaseAction({required this.section});

  factory _$_ConnectDatabaseAction.fromJson(Map<String, dynamic> json) =>
      _$_$_ConnectDatabaseActionFromJson(json);

  @override
  final DatabaseSectionEnum section;

  @override
  String toString() {
    return 'ConnectDatabaseAction(section: $section)';
  }

  @override
  bool operator ==(dynamic other) {
    return identical(this, other) ||
        (other is _ConnectDatabaseAction &&
            (identical(other.section, section) ||
                const DeepCollectionEquality().equals(other.section, section)));
  }

  @override
  int get hashCode =>
      runtimeType.hashCode ^ const DeepCollectionEquality().hash(section);

  @JsonKey(ignore: true)
  @override
  _$ConnectDatabaseActionCopyWith<_ConnectDatabaseAction> get copyWith =>
      __$ConnectDatabaseActionCopyWithImpl<_ConnectDatabaseAction>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$_$_ConnectDatabaseActionToJson(this);
  }
}

abstract class _ConnectDatabaseAction implements ConnectDatabaseAction {
  factory _ConnectDatabaseAction({required DatabaseSectionEnum section}) =
      _$_ConnectDatabaseAction;

  factory _ConnectDatabaseAction.fromJson(Map<String, dynamic> json) =
      _$_ConnectDatabaseAction.fromJson;

  @override
  DatabaseSectionEnum get section => throw _privateConstructorUsedError;
  @override
  @JsonKey(ignore: true)
  _$ConnectDatabaseActionCopyWith<_ConnectDatabaseAction> get copyWith =>
      throw _privateConstructorUsedError;
}
