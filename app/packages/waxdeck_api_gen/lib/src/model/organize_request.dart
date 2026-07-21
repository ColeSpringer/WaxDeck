//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'organize_request.g.dart';

/// The scope of an organize pass.
///
/// Properties:
/// * [profile] - The profile to apply.
/// * [itemPids] - Restrict to these items; absent means the whole library.
@BuiltValue()
abstract class OrganizeRequest implements Built<OrganizeRequest, OrganizeRequestBuilder> {
  /// The profile to apply.
  @BuiltValueField(wireName: r'profile')
  String get profile;

  /// Restrict to these items; absent means the whole library.
  @BuiltValueField(wireName: r'itemPids')
  BuiltList<String>? get itemPids;

  OrganizeRequest._();

  factory OrganizeRequest([void updates(OrganizeRequestBuilder b)]) = _$OrganizeRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OrganizeRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OrganizeRequest> get serializer => _$OrganizeRequestSerializer();
}

class _$OrganizeRequestSerializer implements PrimitiveSerializer<OrganizeRequest> {
  @override
  final Iterable<Type> types = const [OrganizeRequest, _$OrganizeRequest];

  @override
  final String wireName = r'OrganizeRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OrganizeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'profile';
    yield serializers.serialize(
      object.profile,
      specifiedType: const FullType(String),
    );
    if (object.itemPids != null) {
      yield r'itemPids';
      yield serializers.serialize(
        object.itemPids,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    OrganizeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OrganizeRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'profile':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.profile = valueDes;
          break;
        case r'itemPids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.itemPids.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OrganizeRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OrganizeRequestBuilder();
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

