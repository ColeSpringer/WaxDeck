//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/audit_event.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'audit_event_page.g.dart';

/// One page of audit events.
///
/// Properties:
/// * [events] - Events, newest first.
/// * [nextCursor] - Opaque cursor for the next page. Absent on the last page.
@BuiltValue()
abstract class AuditEventPage implements Built<AuditEventPage, AuditEventPageBuilder> {
  /// Events, newest first.
  @BuiltValueField(wireName: r'events')
  BuiltList<AuditEvent> get events;

  /// Opaque cursor for the next page. Absent on the last page.
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  AuditEventPage._();

  factory AuditEventPage([void updates(AuditEventPageBuilder b)]) = _$AuditEventPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AuditEventPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AuditEventPage> get serializer => _$AuditEventPageSerializer();
}

class _$AuditEventPageSerializer implements PrimitiveSerializer<AuditEventPage> {
  @override
  final Iterable<Type> types = const [AuditEventPage, _$AuditEventPage];

  @override
  final String wireName = r'AuditEventPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AuditEventPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'events';
    yield serializers.serialize(
      object.events,
      specifiedType: const FullType(BuiltList, [FullType(AuditEvent)]),
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
    AuditEventPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AuditEventPageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'events':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(AuditEvent)]),
          ) as BuiltList<AuditEvent>;
          result.events.replace(valueDes);
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
  AuditEventPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AuditEventPageBuilder();
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

