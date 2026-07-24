//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'trash_purge_result.g.dart';

/// What purging one trash entry reclaimed.
///
/// Properties:
/// * [reclaimedBytes] - Disk space reclaimed by purging the entry.
@BuiltValue()
abstract class TrashPurgeResult implements Built<TrashPurgeResult, TrashPurgeResultBuilder> {
  /// Disk space reclaimed by purging the entry.
  @BuiltValueField(wireName: r'reclaimedBytes')
  int get reclaimedBytes;

  TrashPurgeResult._();

  factory TrashPurgeResult([void updates(TrashPurgeResultBuilder b)]) = _$TrashPurgeResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TrashPurgeResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TrashPurgeResult> get serializer => _$TrashPurgeResultSerializer();
}

class _$TrashPurgeResultSerializer implements PrimitiveSerializer<TrashPurgeResult> {
  @override
  final Iterable<Type> types = const [TrashPurgeResult, _$TrashPurgeResult];

  @override
  final String wireName = r'TrashPurgeResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TrashPurgeResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'reclaimedBytes';
    yield serializers.serialize(
      object.reclaimedBytes,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    TrashPurgeResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TrashPurgeResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
  TrashPurgeResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TrashPurgeResultBuilder();
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

