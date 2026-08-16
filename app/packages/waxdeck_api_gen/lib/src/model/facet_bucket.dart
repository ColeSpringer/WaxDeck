//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'facet_bucket.g.dart';

/// One bucket of a browse dimension.
///
/// Properties:
/// * [key] - The bucket's stable handle: pass it back as `listItems`' `facetKey` to drill it. Empty for the unknown bucket. 
/// * [label] - Display label. Genre labels are the canonical spelling from the server's genre tree, not whichever variant was scanned first. 
/// * [count] - Items in this bucket, within the caller's libraries.
/// * [entityPid] - The catalog entity behind the bucket, for the dimensions that have one (`artist`, `credit-artist`, `album-artist`, `album`, `release-group`). Absent for the unknown bucket and for dimensions that are not entities. It is this bucket's `key` carried with the entity's API type prefix, so a client holding one has the other: a screen addressed by `al-<ulid>` drills with `facetKey=<ulid>`, and the entity endpoints (`/albums/{pid}/play-state` and friends) take the prefixed form. 
/// * [unknown] - True for the bucket holding items the dimension is absent from. Its `label` is the canonical sentinel and its `key` is empty. 
/// * [letter] - The alphabet-rail row this bucket files under, derived from the same fold that orders `sort=label`: `A` to `Z` when the folded label leads with a Latin letter (accents fold, so \"Édith\" answers `E`), `#` for everything else. The `#` row has members on both sides of the alphabet: digits and most punctuation sort before A, while `{`, `|`, `}`, `~` and every script beyond Latin sort after Z. Present on every real bucket under either sort; absent on the unknown bucket, which has no rail row. A client talking to an older server that omits it derives a letter from `label` itself. 
@BuiltValue()
abstract class FacetBucket implements Built<FacetBucket, FacetBucketBuilder> {
  /// The bucket's stable handle: pass it back as `listItems`' `facetKey` to drill it. Empty for the unknown bucket. 
  @BuiltValueField(wireName: r'key')
  String get key;

  /// Display label. Genre labels are the canonical spelling from the server's genre tree, not whichever variant was scanned first. 
  @BuiltValueField(wireName: r'label')
  String get label;

  /// Items in this bucket, within the caller's libraries.
  @BuiltValueField(wireName: r'count')
  int get count;

  /// The catalog entity behind the bucket, for the dimensions that have one (`artist`, `credit-artist`, `album-artist`, `album`, `release-group`). Absent for the unknown bucket and for dimensions that are not entities. It is this bucket's `key` carried with the entity's API type prefix, so a client holding one has the other: a screen addressed by `al-<ulid>` drills with `facetKey=<ulid>`, and the entity endpoints (`/albums/{pid}/play-state` and friends) take the prefixed form. 
  @BuiltValueField(wireName: r'entityPid')
  String? get entityPid;

  /// True for the bucket holding items the dimension is absent from. Its `label` is the canonical sentinel and its `key` is empty. 
  @BuiltValueField(wireName: r'unknown')
  bool? get unknown;

  /// The alphabet-rail row this bucket files under, derived from the same fold that orders `sort=label`: `A` to `Z` when the folded label leads with a Latin letter (accents fold, so \"Édith\" answers `E`), `#` for everything else. The `#` row has members on both sides of the alphabet: digits and most punctuation sort before A, while `{`, `|`, `}`, `~` and every script beyond Latin sort after Z. Present on every real bucket under either sort; absent on the unknown bucket, which has no rail row. A client talking to an older server that omits it derives a letter from `label` itself. 
  @BuiltValueField(wireName: r'letter')
  String? get letter;

  FacetBucket._();

  factory FacetBucket([void updates(FacetBucketBuilder b)]) = _$FacetBucket;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(FacetBucketBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<FacetBucket> get serializer => _$FacetBucketSerializer();
}

class _$FacetBucketSerializer implements PrimitiveSerializer<FacetBucket> {
  @override
  final Iterable<Type> types = const [FacetBucket, _$FacetBucket];

  @override
  final String wireName = r'FacetBucket';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FacetBucket object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'key';
    yield serializers.serialize(
      object.key,
      specifiedType: const FullType(String),
    );
    yield r'label';
    yield serializers.serialize(
      object.label,
      specifiedType: const FullType(String),
    );
    yield r'count';
    yield serializers.serialize(
      object.count,
      specifiedType: const FullType(int),
    );
    if (object.entityPid != null) {
      yield r'entityPid';
      yield serializers.serialize(
        object.entityPid,
        specifiedType: const FullType(String),
      );
    }
    if (object.unknown != null) {
      yield r'unknown';
      yield serializers.serialize(
        object.unknown,
        specifiedType: const FullType(bool),
      );
    }
    if (object.letter != null) {
      yield r'letter';
      yield serializers.serialize(
        object.letter,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    FacetBucket object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required FacetBucketBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.key = valueDes;
          break;
        case r'label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.label = valueDes;
          break;
        case r'count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.count = valueDes;
          break;
        case r'entityPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.entityPid = valueDes;
          break;
        case r'unknown':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.unknown = valueDes;
          break;
        case r'letter':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.letter = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  FacetBucket deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = FacetBucketBuilder();
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

