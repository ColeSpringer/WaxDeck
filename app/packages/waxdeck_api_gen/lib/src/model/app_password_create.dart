//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'app_password_create.g.dart';

/// A new app password.
///
/// Properties:
/// * [label] - Label shown in the app password list, usually the client app this password is for. 
@BuiltValue()
abstract class AppPasswordCreate implements Built<AppPasswordCreate, AppPasswordCreateBuilder> {
  /// Label shown in the app password list, usually the client app this password is for. 
  @BuiltValueField(wireName: r'label')
  String get label;

  AppPasswordCreate._();

  factory AppPasswordCreate([void updates(AppPasswordCreateBuilder b)]) = _$AppPasswordCreate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AppPasswordCreateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AppPasswordCreate> get serializer => _$AppPasswordCreateSerializer();
}

class _$AppPasswordCreateSerializer implements PrimitiveSerializer<AppPasswordCreate> {
  @override
  final Iterable<Type> types = const [AppPasswordCreate, _$AppPasswordCreate];

  @override
  final String wireName = r'AppPasswordCreate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AppPasswordCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'label';
    yield serializers.serialize(
      object.label,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AppPasswordCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AppPasswordCreateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.label = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AppPasswordCreate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AppPasswordCreateBuilder();
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

