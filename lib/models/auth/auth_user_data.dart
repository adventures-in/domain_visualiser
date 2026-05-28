import 'package:domain_visualiser/models/auth/auth_provider_data.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:domain_visualiser/converters/ilist_converters.dart';

part 'auth_user_data.freezed.dart';
part 'auth_user_data.g.dart';

@freezed
abstract class AuthUserData with _$AuthUserData {
  factory AuthUserData({
    required String uid,
    String? displayName,
    String? photoURL,
    String? email,
    String? phoneNumber,
    DateTime? createdOn,
    DateTime? lastSignedInOn,
    required bool isAnonymous,
    required bool emailVerified,
    @AuthProviderDataIListConverter() required IList<AuthProviderData> providers,
  }) = _AuthUserData;

  factory AuthUserData.fromJson(Map<String, dynamic> json) =>
      _$AuthUserDataFromJson(json);
}
