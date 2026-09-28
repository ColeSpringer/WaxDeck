//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/enrichment_source.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrichment_sources_update.g.dart';

/// The operator's order over the orderable providers.
///
/// Properties:
/// * [sources] - Every provider the status lists that is not `builtin`, in the order they are to be asked. 
@BuiltValue()
abstract class EnrichmentSourcesUpdate implements Built<EnrichmentSourcesUpdate, EnrichmentSourcesUpdateBuilder> {
  /// Every provider the status lists that is not `builtin`, in the order they are to be asked. 
  @BuiltValueField(wireName: r'sources')
  BuiltList<EnrichmentSource> get sources;

  EnrichmentSourcesUpdate._();

  factory EnrichmentSourcesUpdate([void updates(EnrichmentSourcesUpdateBuilder b)]) = _$EnrichmentSourcesUpdate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichmentSourcesUpdateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichmentSourcesUpdate> get serializer => _$EnrichmentSourcesUpdateSerializer();
}

class _$EnrichmentSourcesUpdateSerializer implements PrimitiveSerializer<EnrichmentSourcesUpdate> {
  @override
  final Iterable<Type> types = const [EnrichmentSourcesUpdate, _$EnrichmentSourcesUpdate];

  @override
  final String wireName = r'EnrichmentSourcesUpdate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichmentSourcesUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'sources';
    yield serializers.serialize(
      object.sources,
      specifiedType: const FullType(BuiltList, [FullType(EnrichmentSource)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichmentSourcesUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichmentSourcesUpdateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'sources':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(EnrichmentSource)]),
          ) as BuiltList<EnrichmentSource>;
          result.sources.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichmentSourcesUpdate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichmentSourcesUpdateBuilder();
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


