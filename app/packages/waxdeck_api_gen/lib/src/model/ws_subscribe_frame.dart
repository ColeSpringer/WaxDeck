//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ws_subscribe_frame.g.dart';

/// The WebSocket subscribe frame, sent by the client as the first and only client-to-server message on the event channel (transport in `api/events.md`). Clients pass the cursors their mirror is at; a client with no mirror yet omits them, receives only live invalidations, and snapshots through the sync endpoints (before or after subscribing; both orders are sound because invalidations carry no data). 
///
/// Properties:
/// * [catalogSince] - The client's opaque catalog change cursor.
/// * [serverSince] - The client's opaque server change cursor.
/// * [topics] - Topics to receive (`catalog`, `user`). Omit for all topics. Unknown topic names are ignored. 
@BuiltValue()
abstract class WsSubscribeFrame implements Built<WsSubscribeFrame, WsSubscribeFrameBuilder> {
  /// The client's opaque catalog change cursor.
  @BuiltValueField(wireName: r'catalogSince')
  String? get catalogSince;

  /// The client's opaque server change cursor.
  @BuiltValueField(wireName: r'serverSince')
  String? get serverSince;

  /// Topics to receive (`catalog`, `user`). Omit for all topics. Unknown topic names are ignored. 
  @BuiltValueField(wireName: r'topics')
  BuiltList<String>? get topics;

  WsSubscribeFrame._();

  factory WsSubscribeFrame([void updates(WsSubscribeFrameBuilder b)]) = _$WsSubscribeFrame;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WsSubscribeFrameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WsSubscribeFrame> get serializer => _$WsSubscribeFrameSerializer();
}

class _$WsSubscribeFrameSerializer implements PrimitiveSerializer<WsSubscribeFrame> {
  @override
  final Iterable<Type> types = const [WsSubscribeFrame, _$WsSubscribeFrame];

  @override
  final String wireName = r'WsSubscribeFrame';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WsSubscribeFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.catalogSince != null) {
      yield r'catalogSince';
      yield serializers.serialize(
        object.catalogSince,
        specifiedType: const FullType(String),
      );
    }
    if (object.serverSince != null) {
      yield r'serverSince';
      yield serializers.serialize(
        object.serverSince,
        specifiedType: const FullType(String),
      );
    }
    if (object.topics != null) {
      yield r'topics';
      yield serializers.serialize(
        object.topics,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    WsSubscribeFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WsSubscribeFrameBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'catalogSince':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.catalogSince = valueDes;
          break;
        case r'serverSince':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serverSince = valueDes;
          break;
        case r'topics':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.topics.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WsSubscribeFrame deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WsSubscribeFrameBuilder();
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

