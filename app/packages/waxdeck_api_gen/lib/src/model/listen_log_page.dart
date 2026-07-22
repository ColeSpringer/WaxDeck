//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/listen_log_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'listen_log_page.g.dart';

/// One page of the caller's listen session log, newest first.
///
/// Properties:
/// * [sessions] 
/// * [nextCursor] - Opaque cursor for the next page; absent on the last page.
@BuiltValue()
abstract class ListenLogPage implements Built<ListenLogPage, ListenLogPageBuilder> {
  @BuiltValueField(wireName: r'sessions')
  BuiltList<ListenLogEntry> get sessions;

  /// Opaque cursor for the next page; absent on the last page.
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  ListenLogPage._();

  factory ListenLogPage([void updates(ListenLogPageBuilder b)]) = _$ListenLogPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListenLogPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListenLogPage> get serializer => _$ListenLogPageSerializer();
}

class _$ListenLogPageSerializer implements PrimitiveSerializer<ListenLogPage> {
  @override
  final Iterable<Type> types = const [ListenLogPage, _$ListenLogPage];

  @override
  final String wireName = r'ListenLogPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListenLogPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'sessions';
    yield serializers.serialize(
      object.sessions,
      specifiedType: const FullType(BuiltList, [FullType(ListenLogEntry)]),
    );
    if (object.nextCursor != null) {
      yield r'nextCursor';
      yield serializers.serialize(
        object.nextCursor,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ListenLogPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListenLogPageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'sessions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ListenLogEntry)]),
          ) as BuiltList<ListenLogEntry>;
          result.sessions.replace(valueDes);
          break;
        case r'nextCursor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nextCursor = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ListenLogPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListenLogPageBuilder();
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

