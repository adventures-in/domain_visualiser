import 'package:domain_visualiser/models/auth/auth_provider_data.dart';
import 'package:domain_visualiser/models/domain-objects/domain_object.dart';
import 'package:domain_visualiser/models/navigation/page_data/page_data.dart';
import 'package:domain_visualiser/models/problems/problem.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:json_annotation/json_annotation.dart';

/// JSON converters bridging `fast_immutable_collections` types and the
/// `List`-shaped JSON that `json_serializable` understands.
///
/// `json_serializable` knows how to (de)serialise `List<T>` but not `IList<T>`,
/// so each immutable-collection field carries one of these converters via an
/// annotation (e.g. `@ClassBoxIListConverter()`). Element (de)serialisation is
/// delegated to the element type's own `fromJson` / `toJson`, keeping the
/// converters thin and obvious.

/// Converter for `IList<String>` (primitive elements, no nested codec).
class StringIListConverter
    implements JsonConverter<IList<String>, List<dynamic>> {
  const StringIListConverter();

  @override
  IList<String> fromJson(List<dynamic> json) =>
      json.map((dynamic e) => e as String).toIList();

  @override
  List<dynamic> toJson(IList<String> object) => object.unlockView;
}

class ClassBoxIListConverter
    implements JsonConverter<IList<ClassBox>, List<dynamic>> {
  const ClassBoxIListConverter();

  @override
  IList<ClassBox> fromJson(List<dynamic> json) => json
      .map((dynamic e) => ClassBox.fromJson(e as Map<String, dynamic>))
      .toIList();

  @override
  List<dynamic> toJson(IList<ClassBox> object) =>
      object.map((ClassBox e) => e.toJson()).toList();
}

class PageDataIListConverter
    implements JsonConverter<IList<PageData>, List<dynamic>> {
  const PageDataIListConverter();

  @override
  IList<PageData> fromJson(List<dynamic> json) => json
      .map((dynamic e) => PageData.fromJson(e as Map<String, dynamic>))
      .toIList();

  @override
  List<dynamic> toJson(IList<PageData> object) =>
      object.map((PageData e) => e.toJson()).toList();
}

class ProblemIListConverter
    implements JsonConverter<IList<Problem>, List<dynamic>> {
  const ProblemIListConverter();

  @override
  IList<Problem> fromJson(List<dynamic> json) => json
      .map((dynamic e) => Problem.fromJson(e as Map<String, dynamic>))
      .toIList();

  @override
  List<dynamic> toJson(IList<Problem> object) =>
      object.map((Problem e) => e.toJson()).toList();
}

class AuthProviderDataIListConverter
    implements JsonConverter<IList<AuthProviderData>, List<dynamic>> {
  const AuthProviderDataIListConverter();

  @override
  IList<AuthProviderData> fromJson(List<dynamic> json) => json
      .map((dynamic e) => AuthProviderData.fromJson(e as Map<String, dynamic>))
      .toIList();

  @override
  List<dynamic> toJson(IList<AuthProviderData> object) =>
      object.map((AuthProviderData e) => e.toJson()).toList();
}
