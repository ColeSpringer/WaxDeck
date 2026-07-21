//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrich_item_result.g.dart';

/// What a one-item enrichment fetched.
///
/// Properties:
/// * [applied] - Artifacts fetched and stored, each naming its provider (for example `cover: fanarttv`). 
/// * [skipped] - Artifacts not stored, each naming why (locked, already present, no provider hit, provider unconfigured). 
@BuiltValue()
abstract class EnrichItemResult implements Built<EnrichItemResult, EnrichItemResultBuilder> {
  /// Artifacts fetched and stored, each naming its provider (for example `cover: fanarttv`). 
  @BuiltValueField(wireName: r'applied')
  BuiltList<String> get applied;

  /// Artifacts not stored, each naming why (locked, already present, no provider hit, provider unconfigured). 
  @BuiltValueField(wireName: r'skipped')
  BuiltList<String> get skipped;

  EnrichItemResult._();

  factory EnrichItemResult([void updates(EnrichItemResultBuilder b)]) = _$EnrichItemResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichItemResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichItemResult> get serializer => _$EnrichItemResultSerializer();
}

class _$EnrichItemResultSerializer implements PrimitiveSerializer<EnrichItemResult> {
  @override
  final Iterable<Type> types = const [EnrichItemResult, _$EnrichItemResult];

  @override
  final String wireName = r'EnrichItemResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichItemResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'applied';
    yield serializers.serialize(
      object.applied,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'skipped';
    yield serializers.serialize(
      object.skipped,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichItemResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichItemResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'applied':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.applied.replace(valueDes);
          break;
        case r'skipped':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.skipped.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichItemResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichItemResultBuilder();
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

