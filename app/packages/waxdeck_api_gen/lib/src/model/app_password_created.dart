//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/app_password.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'app_password_created.g.dart';

/// A newly created app password, including its one-time-visible secret.
///
/// Properties:
/// * [id] - App password PID.
/// * [label] - Human-readable label given at creation.
/// * [createdAt] - When the app password was created.
/// * [lastUsedAt] - When the app password last authenticated a request (coarse, minutes). Absent when it has never been used. 
/// * [secret] - The generated password, shown exactly once. The client authenticates against the compatibility APIs with the account's username and this value. 
@BuiltValue()
abstract class AppPasswordCreated implements AppPassword, Built<AppPasswordCreated, AppPasswordCreatedBuilder> {
  /// The generated password, shown exactly once. The client authenticates against the compatibility APIs with the account's username and this value. 
  @BuiltValueField(wireName: r'secret')
  String get secret;

  AppPasswordCreated._();

  factory AppPasswordCreated([void updates(AppPasswordCreatedBuilder b)]) = _$AppPasswordCreated;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AppPasswordCreatedBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AppPasswordCreated> get serializer => _$AppPasswordCreatedSerializer();
}

class _$AppPasswordCreatedSerializer implements PrimitiveSerializer<AppPasswordCreated> {
  @override
  final Iterable<Type> types = const [AppPasswordCreated, _$AppPasswordCreated];

  @override
  final String wireName = r'AppPasswordCreated';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AppPasswordCreated object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'secret';
    yield serializers.serialize(
      object.secret,
      specifiedType: const FullType(String),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'label';
    yield serializers.serialize(
      object.label,
      specifiedType: const FullType(String),
    );
    if (object.lastUsedAt != null) {
      yield r'lastUsedAt';
      yield serializers.serialize(
        object.lastUsedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AppPasswordCreated object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AppPasswordCreatedBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'secret':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.secret = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.label = valueDes;
          break;
        case r'lastUsedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.lastUsedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AppPasswordCreated deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AppPasswordCreatedBuilder();
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

