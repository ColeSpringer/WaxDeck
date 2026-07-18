//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bootstrap_request.g.dart';

/// The first administrator account.
///
/// Properties:
/// * [username] - Administrator login name.
/// * [password] - Administrator password (at least 8 characters).
/// * [displayName] - Optional display name.
@BuiltValue()
abstract class BootstrapRequest implements Built<BootstrapRequest, BootstrapRequestBuilder> {
  /// Administrator login name.
  @BuiltValueField(wireName: r'username')
  String get username;

  /// Administrator password (at least 8 characters).
  @BuiltValueField(wireName: r'password')
  String get password;

  /// Optional display name.
  @BuiltValueField(wireName: r'displayName')
  String? get displayName;

  BootstrapRequest._();

  factory BootstrapRequest([void updates(BootstrapRequestBuilder b)]) = _$BootstrapRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BootstrapRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BootstrapRequest> get serializer => _$BootstrapRequestSerializer();
}

class _$BootstrapRequestSerializer implements PrimitiveSerializer<BootstrapRequest> {
  @override
  final Iterable<Type> types = const [BootstrapRequest, _$BootstrapRequest];

  @override
  final String wireName = r'BootstrapRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BootstrapRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'username';
    yield serializers.serialize(
      object.username,
      specifiedType: const FullType(String),
    );
    yield r'password';
    yield serializers.serialize(
      object.password,
      specifiedType: const FullType(String),
    );
    if (object.displayName != null) {
      yield r'displayName';
      yield serializers.serialize(
        object.displayName,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BootstrapRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BootstrapRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'username':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.username = valueDes;
          break;
        case r'password':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.password = valueDes;
          break;
        case r'displayName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BootstrapRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BootstrapRequestBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

