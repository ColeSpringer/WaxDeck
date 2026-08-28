//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'commit_lyrics.g.dart';

/// Replacement lyrics inside a compound commit. At least one of `lrc` and `plain` must carry content. The write switches live on the commit rather than here. 
///
/// Properties:
/// * [lrc] - Timed lines as LRC text. Malformed lines are skipped and reported as warnings with their line numbers. 
/// * [plain] - A plain unsynchronized block.
@BuiltValue()
abstract class CommitLyrics implements Built<CommitLyrics, CommitLyricsBuilder> {
  /// Timed lines as LRC text. Malformed lines are skipped and reported as warnings with their line numbers. 
  @BuiltValueField(wireName: r'lrc')
  String? get lrc;

  /// A plain unsynchronized block.
  @BuiltValueField(wireName: r'plain')
  String? get plain;

  CommitLyrics._();

  factory CommitLyrics([void updates(CommitLyricsBuilder b)]) = _$CommitLyrics;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CommitLyricsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CommitLyrics> get serializer => _$CommitLyricsSerializer();
}

class _$CommitLyricsSerializer implements PrimitiveSerializer<CommitLyrics> {
  @override
  final Iterable<Type> types = const [CommitLyrics, _$CommitLyrics];

  @override
  final String wireName = r'CommitLyrics';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CommitLyrics object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.lrc != null) {
      yield r'lrc';
      yield serializers.serialize(
        object.lrc,
        specifiedType: const FullType(String),
      );
    }
    if (object.plain != null) {
      yield r'plain';
      yield serializers.serialize(
        object.plain,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CommitLyrics object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CommitLyricsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'lrc':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.lrc = valueDes;
          break;
        case r'plain':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.plain = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CommitLyrics deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CommitLyricsBuilder();
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

