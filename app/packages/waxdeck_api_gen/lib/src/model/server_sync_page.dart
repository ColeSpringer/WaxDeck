//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/server_sync_event.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'server_sync_page.g.dart';

/// One page of the caller's server-side state changes.
///
/// Properties:
/// * [events] - State changes, coalesced within the page.
/// * [nextSince] - Opaque server change cursor to sync from next.
/// * [more] - True when another page is already available; fetch it immediately with `since` set to this page's `nextSince`. 
@BuiltValue()
abstract class ServerSyncPage implements Built<ServerSyncPage, ServerSyncPageBuilder> {
  /// State changes, coalesced within the page.
  @BuiltValueField(wireName: r'events')
  BuiltList<ServerSyncEvent> get events;

  /// Opaque server change cursor to sync from next.
  @BuiltValueField(wireName: r'nextSince')
  String get nextSince;

  /// True when another page is already available; fetch it immediately with `since` set to this page's `nextSince`. 
  @BuiltValueField(wireName: r'more')
  bool? get more;

  ServerSyncPage._();

  factory ServerSyncPage([void updates(ServerSyncPageBuilder b)]) = _$ServerSyncPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ServerSyncPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ServerSyncPage> get serializer => _$ServerSyncPageSerializer();
}

class _$ServerSyncPageSerializer implements PrimitiveSerializer<ServerSyncPage> {
  @override
  final Iterable<Type> types = const [ServerSyncPage, _$ServerSyncPage];

  @override
  final String wireName = r'ServerSyncPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ServerSyncPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'events';
    yield serializers.serialize(
      object.events,
      specifiedType: const FullType(BuiltList, [FullType(ServerSyncEvent)]),
    );
    yield r'nextSince';
    yield serializers.serialize(
      object.nextSince,
      specifiedType: const FullType(String),
    );
    if (object.more != null) {
      yield r'more';
      yield serializers.serialize(
        object.more,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ServerSyncPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ServerSyncPageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'events':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ServerSyncEvent)]),
          ) as BuiltList<ServerSyncEvent>;
          result.events.replace(valueDes);
          break;
        case r'nextSince':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nextSince = valueDes;
          break;
        case r'more':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.more = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ServerSyncPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServerSyncPageBuilder();
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

