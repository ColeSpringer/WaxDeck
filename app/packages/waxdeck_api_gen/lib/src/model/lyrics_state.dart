//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'lyrics_state.g.dart';

/// The stored lyrics, when any.
///
/// Properties:
/// * [synced] - Whether timed lines are stored.
/// * [source_] - Where the stored copy came from: `lrc` (sidecar), `embedded`, or `user`. A string, not a closed enum. 
/// * [lrc] - The lyrics serialized as LRC text (timed lines when synced, bare lines otherwise), the editor's working format. 
@BuiltValue()
abstract class LyricsState implements Built<LyricsState, LyricsStateBuilder> {
  /// Whether timed lines are stored.
  @BuiltValueField(wireName: r'synced')
  bool get synced;

  /// Where the stored copy came from: `lrc` (sidecar), `embedded`, or `user`. A string, not a closed enum. 
  @BuiltValueField(wireName: r'source')
  String get source_;

  /// The lyrics serialized as LRC text (timed lines when synced, bare lines otherwise), the editor's working format. 
  @BuiltValueField(wireName: r'lrc')
  String? get lrc;

  LyricsState._();

  factory LyricsState([void updates(LyricsStateBuilder b)]) = _$LyricsState;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LyricsStateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LyricsState> get serializer => _$LyricsStateSerializer();
}

class _$LyricsStateSerializer implements PrimitiveSerializer<LyricsState> {
  @override
  final Iterable<Type> types = const [LyricsState, _$LyricsState];

  @override
  final String wireName = r'LyricsState';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LyricsState object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'synced';
    yield serializers.serialize(
      object.synced,
      specifiedType: const FullType(bool),
    );
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(String),
    );
    if (object.lrc != null) {
      yield r'lrc';
      yield serializers.serialize(
        object.lrc,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    LyricsState object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LyricsStateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'synced':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.synced = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.source_ = valueDes;
          break;
        case r'lrc':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.lrc = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LyricsState deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LyricsStateBuilder();
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

