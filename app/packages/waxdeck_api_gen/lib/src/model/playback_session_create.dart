//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playback_session_create.g.dart';

/// Start playback of a queue on an endpoint.
///
/// Properties:
/// * [endpointId] - The target endpoint.
/// * [itemPids] - The queue, in play order.
/// * [index] - Zero-based entry to start at. Defaults to 0.
/// * [positionMs] - Position within the starting entry. Defaults to 0.
/// * [play] - Start playing immediately. Defaults to true; false loads paused. 
@BuiltValue()
abstract class PlaybackSessionCreate implements Built<PlaybackSessionCreate, PlaybackSessionCreateBuilder> {
  /// The target endpoint.
  @BuiltValueField(wireName: r'endpointId')
  String get endpointId;

  /// The queue, in play order.
  @BuiltValueField(wireName: r'itemPids')
  BuiltList<String> get itemPids;

  /// Zero-based entry to start at. Defaults to 0.
  @BuiltValueField(wireName: r'index')
  int? get index;

  /// Position within the starting entry. Defaults to 0.
  @BuiltValueField(wireName: r'positionMs')
  int? get positionMs;

  /// Start playing immediately. Defaults to true; false loads paused. 
  @BuiltValueField(wireName: r'play')
  bool? get play;

  PlaybackSessionCreate._();

  factory PlaybackSessionCreate([void updates(PlaybackSessionCreateBuilder b)]) = _$PlaybackSessionCreate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaybackSessionCreateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaybackSessionCreate> get serializer => _$PlaybackSessionCreateSerializer();
}

class _$PlaybackSessionCreateSerializer implements PrimitiveSerializer<PlaybackSessionCreate> {
  @override
  final Iterable<Type> types = const [PlaybackSessionCreate, _$PlaybackSessionCreate];

  @override
  final String wireName = r'PlaybackSessionCreate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaybackSessionCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'endpointId';
    yield serializers.serialize(
      object.endpointId,
      specifiedType: const FullType(String),
    );
    yield r'itemPids';
    yield serializers.serialize(
      object.itemPids,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    if (object.index != null) {
      yield r'index';
      yield serializers.serialize(
        object.index,
        specifiedType: const FullType(int),
      );
    }
    if (object.positionMs != null) {
      yield r'positionMs';
      yield serializers.serialize(
        object.positionMs,
        specifiedType: const FullType(int),
      );
    }
    if (object.play != null) {
      yield r'play';
      yield serializers.serialize(
        object.play,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaybackSessionCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaybackSessionCreateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'endpointId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.endpointId = valueDes;
          break;
        case r'itemPids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.itemPids.replace(valueDes);
          break;
        case r'index':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.index = valueDes;
          break;
        case r'positionMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.positionMs = valueDes;
          break;
        case r'play':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.play = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaybackSessionCreate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaybackSessionCreateBuilder();
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

