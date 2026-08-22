//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'top_entry.g.dart';

/// One top-list entry.
///
/// Properties:
/// * [name] - Display name (artist, album, genre, or show).
/// * [pid] - The entry's pid when the entry is a catalog entity (absent for genres, and for names that no longer resolve). A `stations` entry carries the station's `rs-` pid, which is not a catalog entity but is addressable all the same. 
/// * [artUrl] - Origin-relative artwork URL, when the entry has one. 
/// * [plays] - Listen sessions attributed to the entry in the range.
/// * [ms] - Milliseconds listened in the range.
@BuiltValue()
abstract class TopEntry implements Built<TopEntry, TopEntryBuilder> {
  /// Display name (artist, album, genre, or show).
  @BuiltValueField(wireName: r'name')
  String get name;

  /// The entry's pid when the entry is a catalog entity (absent for genres, and for names that no longer resolve). A `stations` entry carries the station's `rs-` pid, which is not a catalog entity but is addressable all the same. 
  @BuiltValueField(wireName: r'pid')
  String? get pid;

  /// Origin-relative artwork URL, when the entry has one. 
  @BuiltValueField(wireName: r'artUrl')
  String? get artUrl;

  /// Listen sessions attributed to the entry in the range.
  @BuiltValueField(wireName: r'plays')
  int get plays;

  /// Milliseconds listened in the range.
  @BuiltValueField(wireName: r'ms')
  int get ms;

  TopEntry._();

  factory TopEntry([void updates(TopEntryBuilder b)]) = _$TopEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TopEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TopEntry> get serializer => _$TopEntrySerializer();
}

class _$TopEntrySerializer implements PrimitiveSerializer<TopEntry> {
  @override
  final Iterable<Type> types = const [TopEntry, _$TopEntry];

  @override
  final String wireName = r'TopEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TopEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.pid != null) {
      yield r'pid';
      yield serializers.serialize(
        object.pid,
        specifiedType: const FullType(String),
      );
    }
    if (object.artUrl != null) {
      yield r'artUrl';
      yield serializers.serialize(
        object.artUrl,
        specifiedType: const FullType(String),
      );
    }
    yield r'plays';
    yield serializers.serialize(
      object.plays,
      specifiedType: const FullType(int),
    );
    yield r'ms';
    yield serializers.serialize(
      object.ms,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    TopEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TopEntryBuilder result,
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
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'artUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artUrl = valueDes;
          break;
        case r'plays':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.plays = valueDes;
          break;
        case r'ms':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.ms = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TopEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TopEntryBuilder();
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

