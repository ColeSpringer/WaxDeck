//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrichment_provider.g.dart';

/// One enrichment provider.
///
/// Properties:
/// * [name] - Stable provider id.
/// * [capabilities] - What it supplies: `identity`, `genres`, `cover`, `lyrics`, `book`, `aux-art`, `artist-art`, `fields`. Strings, not a closed enum. `cover` is the front cover of a release group; `aux-art` its other slots (back, disc, booklet, background); `artist-art` an artist's own images. The three are separate because they gate separate passes - a provider that only knows front covers must not pull the whole artist catalogue into a walk it cannot answer.  `fields` is scalar metadata with no artwork in it - a track's tempo, ISRC or composer, an album's label or year - and gates the two fields walks, one per rung. `book` covers the same ground for audiobooks (publisher, narrator, the identifiers) and gates the book walk. 
/// * [configured] - Whether the provider can run: a keyed one once its key is set, a built-in once the MusicBrainz contact is. Key-free is not the same as configured - the built-ins are public services that want an identifying agent, and the catalog does not register them without one. 
/// * [builtin] - True for the catalog's built-ins.
@BuiltValue()
abstract class EnrichmentProvider implements Built<EnrichmentProvider, EnrichmentProviderBuilder> {
  /// Stable provider id.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// What it supplies: `identity`, `genres`, `cover`, `lyrics`, `book`, `aux-art`, `artist-art`, `fields`. Strings, not a closed enum. `cover` is the front cover of a release group; `aux-art` its other slots (back, disc, booklet, background); `artist-art` an artist's own images. The three are separate because they gate separate passes - a provider that only knows front covers must not pull the whole artist catalogue into a walk it cannot answer.  `fields` is scalar metadata with no artwork in it - a track's tempo, ISRC or composer, an album's label or year - and gates the two fields walks, one per rung. `book` covers the same ground for audiobooks (publisher, narrator, the identifiers) and gates the book walk. 
  @BuiltValueField(wireName: r'capabilities')
  BuiltList<String> get capabilities;

  /// Whether the provider can run: a keyed one once its key is set, a built-in once the MusicBrainz contact is. Key-free is not the same as configured - the built-ins are public services that want an identifying agent, and the catalog does not register them without one. 
  @BuiltValueField(wireName: r'configured')
  bool get configured;

  /// True for the catalog's built-ins.
  @BuiltValueField(wireName: r'builtin')
  bool get builtin;

  EnrichmentProvider._();

  factory EnrichmentProvider([void updates(EnrichmentProviderBuilder b)]) = _$EnrichmentProvider;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichmentProviderBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichmentProvider> get serializer => _$EnrichmentProviderSerializer();
}

class _$EnrichmentProviderSerializer implements PrimitiveSerializer<EnrichmentProvider> {
  @override
  final Iterable<Type> types = const [EnrichmentProvider, _$EnrichmentProvider];

  @override
  final String wireName = r'EnrichmentProvider';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichmentProvider object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'capabilities';
    yield serializers.serialize(
      object.capabilities,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'configured';
    yield serializers.serialize(
      object.configured,
      specifiedType: const FullType(bool),
    );
    yield r'builtin';
    yield serializers.serialize(
      object.builtin,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichmentProvider object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichmentProviderBuilder result,
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
        case r'capabilities':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.capabilities.replace(valueDes);
          break;
        case r'configured':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.configured = valueDes;
          break;
        case r'builtin':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.builtin = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichmentProvider deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichmentProviderBuilder();
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

