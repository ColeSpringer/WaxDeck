//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'app_password.g.dart';

/// One app password, without its secret.
///
/// Properties:
/// * [id] - App password PID.
/// * [label] - Human-readable label given at creation.
/// * [createdAt] - When the app password was created.
/// * [lastUsedAt] - When the app password last authenticated a request (coarse, minutes). Absent when it has never been used. 
@BuiltValue(instantiable: false)
abstract class AppPassword  {
  /// App password PID.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// Human-readable label given at creation.
  @BuiltValueField(wireName: r'label')
  String get label;

  /// When the app password was created.
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  /// When the app password last authenticated a request (coarse, minutes). Absent when it has never been used. 
  @BuiltValueField(wireName: r'lastUsedAt')
  DateTime? get lastUsedAt;

  @BuiltValueSerializer(custom: true)
  static Serializer<AppPassword> get serializer => _$AppPasswordSerializer();
}

class _$AppPasswordSerializer implements PrimitiveSerializer<AppPassword> {
  @override
  final Iterable<Type> types = const [AppPassword];

  @override
  final String wireName = r'AppPassword';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AppPassword object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
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
    AppPassword object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  @override
  AppPassword deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.deserialize(serialized, specifiedType: FullType($AppPassword)) as $AppPassword;
  }
}

/// a concrete implementation of [AppPassword], since [AppPassword] is not instantiable
@BuiltValue(instantiable: true)
abstract class $AppPassword implements AppPassword, Built<$AppPassword, $AppPasswordBuilder> {
  $AppPassword._();

  factory $AppPassword([void Function($AppPasswordBuilder)? updates]) = _$$AppPassword;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults($AppPasswordBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<$AppPassword> get serializer => _$$AppPasswordSerializer();
}

class _$$AppPasswordSerializer implements PrimitiveSerializer<$AppPassword> {
  @override
  final Iterable<Type> types = const [$AppPassword, _$$AppPassword];

  @override
  final String wireName = r'$AppPassword';

  @override
  Object serialize(
    Serializers serializers,
    $AppPassword object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.serialize(object, specifiedType: FullType(AppPassword))!;
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AppPasswordBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
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
  $AppPassword deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = $AppPasswordBuilder();
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

