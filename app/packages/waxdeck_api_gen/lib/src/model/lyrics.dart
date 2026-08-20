//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/synced_line.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'lyrics.g.dart';

/// Lyrics for one item. At least one of `synced` and `unsynced` is non-empty. 
///
/// Properties:
/// * [pid] - The item these lyrics belong to.
/// * [source_] - Where the lyrics came from: `tag` (an embedded USLT/SYLT frame), `sidecar` (an `.lrc` beside the audio), `user`, or `enrichment`. The same vocabulary artwork reports; it replaces the older `lrc`/`embedded` pair, which named formats rather than producers. 
/// * [provider] - The lyrics provider that supplied an `enrichment` copy. Empty for every other source. 
/// * [synced] - Time-synced lines, ordered by `timeMs`.
/// * [unsynced] - Plain text block when no synced lines exist.
@BuiltValue()
abstract class Lyrics implements Built<Lyrics, LyricsBuilder> {
  /// The item these lyrics belong to.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Where the lyrics came from: `tag` (an embedded USLT/SYLT frame), `sidecar` (an `.lrc` beside the audio), `user`, or `enrichment`. The same vocabulary artwork reports; it replaces the older `lrc`/`embedded` pair, which named formats rather than producers. 
  @BuiltValueField(wireName: r'source')
  String get source_;

  /// The lyrics provider that supplied an `enrichment` copy. Empty for every other source. 
  @BuiltValueField(wireName: r'provider')
  String? get provider;

  /// Time-synced lines, ordered by `timeMs`.
  @BuiltValueField(wireName: r'synced')
  BuiltList<SyncedLine>? get synced;

  /// Plain text block when no synced lines exist.
  @BuiltValueField(wireName: r'unsynced')
  String? get unsynced;

  Lyrics._();

  factory Lyrics([void updates(LyricsBuilder b)]) = _$Lyrics;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LyricsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Lyrics> get serializer => _$LyricsSerializer();
}

class _$LyricsSerializer implements PrimitiveSerializer<Lyrics> {
  @override
  final Iterable<Type> types = const [Lyrics, _$Lyrics];

  @override
  final String wireName = r'Lyrics';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Lyrics object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(String),
    );
    if (object.provider != null) {
      yield r'provider';
      yield serializers.serialize(
        object.provider,
        specifiedType: const FullType(String),
      );
    }
    if (object.synced != null) {
      yield r'synced';
      yield serializers.serialize(
        object.synced,
        specifiedType: const FullType(BuiltList, [FullType(SyncedLine)]),
      );
    }
    if (object.unsynced != null) {
      yield r'unsynced';
      yield serializers.serialize(
        object.unsynced,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Lyrics object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LyricsBuilder result,
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
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.source_ = valueDes;
          break;
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.provider = valueDes;
          break;
        case r'synced':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(SyncedLine)]),
          ) as BuiltList<SyncedLine>;
          result.synced.replace(valueDes);
          break;
        case r'unsynced':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.unsynced = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Lyrics deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LyricsBuilder();
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

