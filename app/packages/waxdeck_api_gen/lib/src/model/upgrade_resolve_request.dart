//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upgrade_resolve_request.g.dart';

/// Keep one encoding, trash the rest: by item across items, or by file within one. 
///
/// Properties:
/// * [keepItemPid] - The item to keep, or the item whose files these are.
/// * [removeItemPids] - The inferior encodings to trash, as whole items.
/// * [keepFilePid] - The file to keep, within `keepItemPid`; required with `removeFilePids`. 
/// * [removeFilePids] - The inferior encodings to trash, as files of `keepItemPid`.
@BuiltValue()
abstract class UpgradeResolveRequest implements Built<UpgradeResolveRequest, UpgradeResolveRequestBuilder> {
  /// The item to keep, or the item whose files these are.
  @BuiltValueField(wireName: r'keepItemPid')
  String get keepItemPid;

  /// The inferior encodings to trash, as whole items.
  @BuiltValueField(wireName: r'removeItemPids')
  BuiltList<String>? get removeItemPids;

  /// The file to keep, within `keepItemPid`; required with `removeFilePids`. 
  @BuiltValueField(wireName: r'keepFilePid')
  String? get keepFilePid;

  /// The inferior encodings to trash, as files of `keepItemPid`.
  @BuiltValueField(wireName: r'removeFilePids')
  BuiltList<String>? get removeFilePids;

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
    if (object.removeItemPids != null) {
      yield r'removeItemPids';
      yield serializers.serialize(
        object.removeItemPids,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.keepFilePid != null) {
      yield r'keepFilePid';
      yield serializers.serialize(
        object.keepFilePid,
        specifiedType: const FullType(String),
      );
    }
    if (object.removeFilePids != null) {
      yield r'removeFilePids';
      yield serializers.serialize(
        object.removeFilePids,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
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
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.removeItemPids.replace(valueDes);
          break;
        case r'keepFilePid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.keepFilePid = valueDes;
          break;
        case r'removeFilePids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.removeFilePids.replace(valueDes);
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


