//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/timeline_format.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'timeline_create.g.dart';

/// Mint a gapless timeline over an ordered queue of items.
///
/// Properties:
/// * [itemPids] - The queue, in play order.
/// * [crossfadeSeconds] - Equal-power crossfade applied at every seam, in seconds, 0 to 12. Omit or 0 for a gapless butt join. The value shapes the returned boundaries; the served stream applies the same value by construction. 
/// * [formats] - Audio formats this caller can decode, most preferred first. The timeline is rendered in the first one the server can produce; when none of them fit it falls back to its own ladder, and `format` on the answer always says which was chosen. Omit it when whatever the server picks will play. The format is part of what identifies a timeline, so two callers asking for different ones get different streams over the same queue rather than one overwriting the other. 
@BuiltValue()
abstract class TimelineCreate implements Built<TimelineCreate, TimelineCreateBuilder> {
  /// The queue, in play order.
  @BuiltValueField(wireName: r'itemPids')
  BuiltList<String> get itemPids;

  /// Equal-power crossfade applied at every seam, in seconds, 0 to 12. Omit or 0 for a gapless butt join. The value shapes the returned boundaries; the served stream applies the same value by construction. 
  @BuiltValueField(wireName: r'crossfadeSeconds')
  double? get crossfadeSeconds;

  /// Audio formats this caller can decode, most preferred first. The timeline is rendered in the first one the server can produce; when none of them fit it falls back to its own ladder, and `format` on the answer always says which was chosen. Omit it when whatever the server picks will play. The format is part of what identifies a timeline, so two callers asking for different ones get different streams over the same queue rather than one overwriting the other. 
  @BuiltValueField(wireName: r'formats')
  BuiltList<TimelineFormat>? get formats;

  TimelineCreate._();

  factory TimelineCreate([void updates(TimelineCreateBuilder b)]) = _$TimelineCreate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TimelineCreateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TimelineCreate> get serializer => _$TimelineCreateSerializer();
}

class _$TimelineCreateSerializer implements PrimitiveSerializer<TimelineCreate> {
  @override
  final Iterable<Type> types = const [TimelineCreate, _$TimelineCreate];

  @override
  final String wireName = r'TimelineCreate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TimelineCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'itemPids';
    yield serializers.serialize(
      object.itemPids,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    if (object.crossfadeSeconds != null) {
      yield r'crossfadeSeconds';
      yield serializers.serialize(
        object.crossfadeSeconds,
        specifiedType: const FullType(double),
      );
    }
    if (object.formats != null) {
      yield r'formats';
      yield serializers.serialize(
        object.formats,
        specifiedType: const FullType(BuiltList, [FullType(TimelineFormat)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    TimelineCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TimelineCreateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'itemPids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.itemPids.replace(valueDes);
          break;
        case r'crossfadeSeconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.crossfadeSeconds = valueDes;
          break;
        case r'formats':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(TimelineFormat)]),
          ) as BuiltList<TimelineFormat>;
          result.formats.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TimelineCreate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TimelineCreateBuilder();
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

