//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/app_password.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'app_password_list.g.dart';

/// The caller's app passwords, newest first.
///
/// Properties:
/// * [appPasswords] 
@BuiltValue()
abstract class AppPasswordList implements Built<AppPasswordList, AppPasswordListBuilder> {
  @BuiltValueField(wireName: r'appPasswords')
  BuiltList<AppPassword> get appPasswords;

  AppPasswordList._();

  factory AppPasswordList([void updates(AppPasswordListBuilder b)]) = _$AppPasswordList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AppPasswordListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AppPasswordList> get serializer => _$AppPasswordListSerializer();
}

class _$AppPasswordListSerializer implements PrimitiveSerializer<AppPasswordList> {
  @override
  final Iterable<Type> types = const [AppPasswordList, _$AppPasswordList];

  @override
  final String wireName = r'AppPasswordList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AppPasswordList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'appPasswords';
    yield serializers.serialize(
      object.appPasswords,
      specifiedType: const FullType(BuiltList, [FullType(AppPassword)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AppPasswordList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AppPasswordListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'appPasswords':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(AppPassword)]),
          ) as BuiltList<AppPassword>;
          result.appPasswords.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AppPasswordList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AppPasswordListBuilder();
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

