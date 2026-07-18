//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'search_hit.g.dart';

/// One ranked search hit.
///
/// Properties:
/// * [pid] - Type-prefixed ULID of the hit.
/// * [kind] - What the hit is (`artist`, `album`, `track`, `book`, `episode`).
/// * [title] - Display title.
/// * [subtitle] - Context line (artist for a track, author for a book).
@BuiltValue()
abstract class SearchHit implements Built<SearchHit, SearchHitBuilder> {
  /// Type-prefixed ULID of the hit.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// What the hit is (`artist`, `album`, `track`, `book`, `episode`).
  @BuiltValueField(wireName: r'kind')
  String get kind;

  /// Display title.
  @BuiltValueField(wireName: r'title')
  String get title;

  /// Context line (artist for a track, author for a book).
  @BuiltValueField(wireName: r'subtitle')
  String? get subtitle;

  SearchHit._();

  factory SearchHit([void updates(SearchHitBuilder b)]) = _$SearchHit;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SearchHitBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SearchHit> get serializer => _$SearchHitSerializer();
}

class _$SearchHitSerializer implements PrimitiveSerializer<SearchHit> {
  @override
  final Iterable<Type> types = const [SearchHit, _$SearchHit];

  @override
  final String wireName = r'SearchHit';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SearchHit object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(String),
    );
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    if (object.subtitle != null) {
      yield r'subtitle';
      yield serializers.serialize(
        object.subtitle,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SearchHit object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SearchHitBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.kind = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'subtitle':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.subtitle = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SearchHit deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SearchHitBuilder();
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

