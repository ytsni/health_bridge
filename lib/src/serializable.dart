part of '../health.dart';

/// A registry that maps `$type` strings to `fromJson` functions for
/// polymorphic deserialization of [Serializable] subclasses.
///
/// Inlined from the `carp_serializable` package to remove the external dependency.
class FromJsonFactory {
  static final FromJsonFactory _instance = FromJsonFactory._();
  factory FromJsonFactory() => _instance;
  FromJsonFactory._();

  final Map<String, Function> _registry = {};

  void register(Serializable instance) {
    _registry[instance.runtimeType.toString()] = instance.fromJsonFunction;
  }

  void registerAll(List<Serializable> instances) {
    for (final instance in instances) {
      register(instance);
    }
  }

  T fromJson<T extends Serializable>(Map<String, dynamic> json) {
    // Public model codecs must not depend on constructing the platform plugin
    // first. Registration is idempotent and does not deserialize recursively.
    _registerFromJsonFunctions();
    final type = json[Serializable.typeKey];
    final function = _registry[type];
    if (function == null) {
      throw SerializationException(
        "No fromJson function registered for type '$type'. "
        "Register it using FromJsonFactory().register().",
      );
    }
    return Function.apply(function, [json]) as T;
  }
}

/// Base class for polymorphic JSON serialization.
///
/// Subclasses must override [fromJsonFunction] and [toJson].
/// The `$type` field is automatically included in JSON output for deserialization.
abstract class Serializable {
  static const String typeKey = '\$type';

  @JsonKey(name: r'$type')
  String $type;

  Serializable() : $type = '' {
    $type = runtimeType.toString();
  }

  Function get fromJsonFunction;
  Map<String, dynamic> toJson();
}

class SerializationException implements Exception {
  final String message;
  SerializationException(this.message);

  @override
  String toString() => 'SerializationException: $message';
}
