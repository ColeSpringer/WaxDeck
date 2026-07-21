//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'lyrics_edit.g.dart';

/// Replacement lyrics. At least one of `lrc` and `plain` must carry content. 
///
/// Properties:
/// * [lrc] - Timed lines as LRC text. Malformed lines are skipped and reported as warnings with their line numbers. 
/// * [plain] - A plain unsynchronized block.
/// * [writeBack] - Write the `.lrc` sidecar next to the file and embed where the format allows. 
/// * [lock] - Lock the lyrics artifact.
/// * [force] - Override an existing lock.
@BuiltValue()
abstract class LyricsEdit implements Built<LyricsEdit, LyricsEditBuilder> {
  /// Timed lines as LRC text. Malformed lines are skipped and reported as warnings with their line numbers. 
  @BuiltValueField(wireName: r'lrc')
  String? get lrc;

  /// A plain unsynchronized block.
  @BuiltValueField(wireName: r'plain')
  String? get plain;

  /// Write the `.lrc` sidecar next to the file and embed where the format allows. 
  @BuiltValueField(wireName: r'writeBack')
  bool? get writeBack;

  /// Lock the lyrics artifact.
  @BuiltValueField(wireName: r'lock')
  bool? get lock;

  /// Override an existing lock.
  @BuiltValueField(wireName: r'force')
  bool? get force;

  LyricsEdit._();

  factory LyricsEdit([void updates(LyricsEditBuilder b)]) = _$LyricsEdit;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LyricsEditBuilder b) => b
      ..writeBack = false
      ..lock = true
      ..force = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<LyricsEdit> get serializer => _$LyricsEditSerializer();
}

class _$LyricsEditSerializer implements PrimitiveSerializer<LyricsEdit> {
  @override
  final Iterable<Type> types = const [LyricsEdit, _$LyricsEdit];

  @override
  final String wireName = r'LyricsEdit';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LyricsEdit object, {
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
    if (object.writeBack != null) {
      yield r'writeBack';
      yield serializers.serialize(
        object.writeBack,
        specifiedType: const FullType(bool),
      );
    }
    if (object.lock != null) {
      yield r'lock';
      yield serializers.serialize(
        object.lock,
        specifiedType: const FullType(bool),
      );
    }
    if (object.force != null) {
      yield r'force';
      yield serializers.serialize(
        object.force,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    LyricsEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LyricsEditBuilder result,
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
        case r'writeBack':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.writeBack = valueDes;
          break;
        case r'lock':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.lock = valueDes;
          break;
        case r'force':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.force = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LyricsEdit deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LyricsEditBuilder();
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

