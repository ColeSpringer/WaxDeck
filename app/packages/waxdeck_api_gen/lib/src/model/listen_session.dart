//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'listen_session.g.dart';

/// One listen session as reported by a client. `sessionId` is a client-generated idempotency ID; replaying a session with the same ID never double-counts. Deduplication is per user across all of the user's clients, so IDs must be globally random (ULID or UUID), never a per-device counter. 
///
/// Properties:
/// * [sessionId] - Client-generated idempotency ID for this session, unique across all of the user's clients (use a ULID or UUID). 
/// * [pid] - The item that was played.
/// * [startedAt] - When playback started. Historical for backdated imports; the server preserves it as reported. 
/// * [msPlayed] - Milliseconds actually heard (excludes pauses and seeks).
/// * [skippedMs] - Milliseconds of content the listener did not sit through thanks to silence trimming and playback speed above 1x, for the time-saved counter. Omit when neither applies. 
/// * [finished] - Whether playback reached the end of the item.
/// * [client] - Client identifier (app name and platform).
/// * [source_] - Where the session originates. `live` is a WaxDeck client reporting its own playback; `import` is a backdated session from another service's history. 
@BuiltValue()
abstract class ListenSession implements Built<ListenSession, ListenSessionBuilder> {
  /// Client-generated idempotency ID for this session, unique across all of the user's clients (use a ULID or UUID). 
  @BuiltValueField(wireName: r'sessionId')
  String get sessionId;

  /// The item that was played.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// When playback started. Historical for backdated imports; the server preserves it as reported. 
  @BuiltValueField(wireName: r'startedAt')
  DateTime get startedAt;

  /// Milliseconds actually heard (excludes pauses and seeks).
  @BuiltValueField(wireName: r'msPlayed')
  int get msPlayed;

  /// Milliseconds of content the listener did not sit through thanks to silence trimming and playback speed above 1x, for the time-saved counter. Omit when neither applies. 
  @BuiltValueField(wireName: r'skippedMs')
  int? get skippedMs;

  /// Whether playback reached the end of the item.
  @BuiltValueField(wireName: r'finished')
  bool? get finished;

  /// Client identifier (app name and platform).
  @BuiltValueField(wireName: r'client')
  String? get client;

  /// Where the session originates. `live` is a WaxDeck client reporting its own playback; `import` is a backdated session from another service's history. 
  @BuiltValueField(wireName: r'source')
  ListenSessionSource_Enum? get source_;
  // enum source_Enum {  live,  import,  };

  ListenSession._();

  factory ListenSession([void updates(ListenSessionBuilder b)]) = _$ListenSession;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListenSessionBuilder b) => b
      ..source_ = const ListenSessionSource_Enum._('live');

  @BuiltValueSerializer(custom: true)
  static Serializer<ListenSession> get serializer => _$ListenSessionSerializer();
}

class _$ListenSessionSerializer implements PrimitiveSerializer<ListenSession> {
  @override
  final Iterable<Type> types = const [ListenSession, _$ListenSession];

  @override
  final String wireName = r'ListenSession';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListenSession object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'sessionId';
    yield serializers.serialize(
      object.sessionId,
      specifiedType: const FullType(String),
    );
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'startedAt';
    yield serializers.serialize(
      object.startedAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'msPlayed';
    yield serializers.serialize(
      object.msPlayed,
      specifiedType: const FullType(int),
    );
    if (object.skippedMs != null) {
      yield r'skippedMs';
      yield serializers.serialize(
        object.skippedMs,
        specifiedType: const FullType(int),
      );
    }
    if (object.finished != null) {
      yield r'finished';
      yield serializers.serialize(
        object.finished,
        specifiedType: const FullType(bool),
      );
    }
    if (object.client != null) {
      yield r'client';
      yield serializers.serialize(
        object.client,
        specifiedType: const FullType(String),
      );
    }
    if (object.source_ != null) {
      yield r'source';
      yield serializers.serialize(
        object.source_,
        specifiedType: const FullType(ListenSessionSource_Enum),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ListenSession object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListenSessionBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'sessionId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sessionId = valueDes;
          break;
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'startedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.startedAt = valueDes;
          break;
        case r'msPlayed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.msPlayed = valueDes;
          break;
        case r'skippedMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.skippedMs = valueDes;
          break;
        case r'finished':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.finished = valueDes;
          break;
        case r'client':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.client = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ListenSessionSource_Enum),
          ) as ListenSessionSource_Enum;
          result.source_ = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ListenSession deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListenSessionBuilder();
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

class ListenSessionSource_Enum extends EnumClass {

  /// Where the session originates. `live` is a WaxDeck client reporting its own playback; `import` is a backdated session from another service's history. 
  @BuiltValueEnumConst(wireName: r'live')
  static const ListenSessionSource_Enum live = _$listenSessionSourceEnum_live;
  /// Where the session originates. `live` is a WaxDeck client reporting its own playback; `import` is a backdated session from another service's history. 
  @BuiltValueEnumConst(wireName: r'import')
  static const ListenSessionSource_Enum import_ = _$listenSessionSourceEnum_import_;

  static Serializer<ListenSessionSource_Enum> get serializer => _$listenSessionSourceEnumSerializer;

  const ListenSessionSource_Enum._(String name): super(name);

  static BuiltSet<ListenSessionSource_Enum> get values => _$listenSessionSourceEnumValues;
  static ListenSessionSource_Enum valueOf(String name) => _$listenSessionSourceEnumValueOf(name);
}

