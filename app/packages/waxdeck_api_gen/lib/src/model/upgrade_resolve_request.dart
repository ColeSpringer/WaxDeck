//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upgrade_resolve_request.g.dart';

/// Keep one encoding, trash the rest.
///
/// Properties:
/// * [keepItemPid] - The item to keep.
/// * [removeItemPids] - The inferior encodings to trash.
@BuiltValue()
abstract class UpgradeResolveRequest implements Built<UpgradeResolveRequest, UpgradeResolveRequestBuilder> {
  /// The item to keep.
  @BuiltValueField(wireName: r'keepItemPid')
  String get keepItemPid;

  /// The inferior encodings to trash.
  @BuiltValueField(wireName: r'removeItemPids')
  BuiltList<String> get removeItemPids;

  UpgradeResolveRequest._();

  factory UpgradeResolveRequest([void updates(UpgradeResolveRequestBuilder b)]) = _$UpgradeResolveRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpgradeResolveRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpgradeResolveRequest> get serializer => _$UpgradeResolveRequestSerializer();
}

class _$UpgradeResolveRequestSerializer implements PrimitiveSerializer<UpgradeResolveRequest> {
  @override
  final Iterable<Type> types = const [UpgradeResolveRequest, _$UpgradeResolveRequest];

  @override
  final String wireName = r'UpgradeResolveRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpgradeResolveRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'keepItemPid';
    yield serializers.serialize(
      object.keepItemPid,
      specifiedType: const FullType(String),
    );
    yield r'removeItemPids';
    yield serializers.serialize(
      object.removeItemPids,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UpgradeResolveRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UpgradeResolveRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'keepItemPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.keepItemPid = valueDes;
          break;
        case r'removeItemPids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.removeItemPids.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpgradeResolveRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpgradeResolveRequestBuilder();
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

