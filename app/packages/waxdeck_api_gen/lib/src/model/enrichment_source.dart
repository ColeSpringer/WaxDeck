//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrichment_source.g.dart';

/// One provider's place in the order, and its switch.
///
/// Properties:
/// * [name] - The provider's `name` from the status.
/// * [enabled] - Whether it is asked.
@BuiltValue()
abstract class EnrichmentSource implements Built<EnrichmentSource, EnrichmentSourceBuilder> {
  /// The provider's `name` from the status.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Whether it is asked.
  @BuiltValueField(wireName: r'enabled')
  bool get enabled;

  EnrichmentSource._();

  factory EnrichmentSource([void updates(EnrichmentSourceBuilder b)]) = _$EnrichmentSource;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichmentSourceBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichmentSource> get serializer => _$EnrichmentSourceSerializer();
}

class _$EnrichmentSourceSerializer implements PrimitiveSerializer<EnrichmentSource> {
  @override
  final Iterable<Type> types = const [EnrichmentSource, _$EnrichmentSource];

  @override
  final String wireName = r'EnrichmentSource';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichmentSource object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'enabled';
    yield serializers.serialize(
      object.enabled,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichmentSource object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichmentSourceBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'enabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.enabled = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichmentSource deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichmentSourceBuilder();
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


