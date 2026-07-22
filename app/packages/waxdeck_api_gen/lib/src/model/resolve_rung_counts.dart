//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'resolve_rung_counts.g.dart';

/// How many entries each resolve-ladder rung matched, most confident rung first. A high `descriptive` share means fuzzy matches worth spot-checking. 
///
/// Properties:
/// * [essence] - Identical audio bytes.
/// * [strongId] - Exact external identifier (recording MBID, ASIN, ISBN).
/// * [fingerprint] - Same recording, different encoding.
/// * [descriptive] - Fuzzy artist, title, album, and duration match.
@BuiltValue()
abstract class ResolveRungCounts implements Built<ResolveRungCounts, ResolveRungCountsBuilder> {
  /// Identical audio bytes.
  @BuiltValueField(wireName: r'essence')
  int get essence;

  /// Exact external identifier (recording MBID, ASIN, ISBN).
  @BuiltValueField(wireName: r'strongId')
  int get strongId;

  /// Same recording, different encoding.
  @BuiltValueField(wireName: r'fingerprint')
  int get fingerprint;

  /// Fuzzy artist, title, album, and duration match.
  @BuiltValueField(wireName: r'descriptive')
  int get descriptive;

  ResolveRungCounts._();

  factory ResolveRungCounts([void updates(ResolveRungCountsBuilder b)]) = _$ResolveRungCounts;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ResolveRungCountsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ResolveRungCounts> get serializer => _$ResolveRungCountsSerializer();
}

class _$ResolveRungCountsSerializer implements PrimitiveSerializer<ResolveRungCounts> {
  @override
  final Iterable<Type> types = const [ResolveRungCounts, _$ResolveRungCounts];

  @override
  final String wireName = r'ResolveRungCounts';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ResolveRungCounts object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'essence';
    yield serializers.serialize(
      object.essence,
      specifiedType: const FullType(int),
    );
    yield r'strongId';
    yield serializers.serialize(
      object.strongId,
      specifiedType: const FullType(int),
    );
    yield r'fingerprint';
    yield serializers.serialize(
      object.fingerprint,
      specifiedType: const FullType(int),
    );
    yield r'descriptive';
    yield serializers.serialize(
      object.descriptive,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ResolveRungCounts object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ResolveRungCountsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'essence':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.essence = valueDes;
          break;
        case r'strongId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.strongId = valueDes;
          break;
        case r'fingerprint':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.fingerprint = valueDes;
          break;
        case r'descriptive':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.descriptive = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ResolveRungCounts deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ResolveRungCountsBuilder();
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

