//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'trash_empty_result.g.dart';

/// What an empty-trash pass did.
///
/// Properties:
/// * [purged] - Files permanently deleted.
/// * [errored] - Files that could not be purged (retry later).
/// * [reclaimedBytes] - Disk space reclaimed.
@BuiltValue()
abstract class TrashEmptyResult implements Built<TrashEmptyResult, TrashEmptyResultBuilder> {
  /// Files permanently deleted.
  @BuiltValueField(wireName: r'purged')
  int get purged;

  /// Files that could not be purged (retry later).
  @BuiltValueField(wireName: r'errored')
  int get errored;

  /// Disk space reclaimed.
  @BuiltValueField(wireName: r'reclaimedBytes')
  int get reclaimedBytes;

  TrashEmptyResult._();

  factory TrashEmptyResult([void updates(TrashEmptyResultBuilder b)]) = _$TrashEmptyResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TrashEmptyResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TrashEmptyResult> get serializer => _$TrashEmptyResultSerializer();
}

class _$TrashEmptyResultSerializer implements PrimitiveSerializer<TrashEmptyResult> {
  @override
  final Iterable<Type> types = const [TrashEmptyResult, _$TrashEmptyResult];

  @override
  final String wireName = r'TrashEmptyResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TrashEmptyResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'purged';
    yield serializers.serialize(
      object.purged,
      specifiedType: const FullType(int),
    );
    yield r'errored';
    yield serializers.serialize(
      object.errored,
      specifiedType: const FullType(int),
    );
    yield r'reclaimedBytes';
    yield serializers.serialize(
      object.reclaimedBytes,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    TrashEmptyResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TrashEmptyResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'purged':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.purged = valueDes;
          break;
        case r'errored':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.errored = valueDes;
          break;
        case r'reclaimedBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.reclaimedBytes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TrashEmptyResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TrashEmptyResultBuilder();
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

