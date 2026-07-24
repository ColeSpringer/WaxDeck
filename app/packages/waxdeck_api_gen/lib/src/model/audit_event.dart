//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'audit_event.g.dart';

/// One recorded administrative action.
///
/// Properties:
/// * [id] - Opaque event id, unique and time-ordered.
/// * [actorId] - The acting user's PID; absent for server-initiated actions (scheduled jobs, startup restore). 
/// * [actorName] - The acting username at the time of the action (kept verbatim if the account is later renamed or deleted). 
/// * [action] - Dotted action name, resource first: `user.create`, `user.update`, `user.delete`, `user.approve`, `user.reject`, `invite.create`, `invite.revoke`, `playlist.delete`, `items.delete`, `entity.merge`, `trash.restore`, `trash.empty`, `backup.create`, `backup.delete`, `restore.stage`, `restore.apply`, `settings.update`, `schedule.update`, `library.create`, `library.read-only`, `transcoding.update`, `migration.run`, and more as surfaces grow. Open vocabulary; filter by prefix. 
/// * [targetKind] - What kind of thing was acted on (`user`, `playlist`, ...).
/// * [targetPid] - The acted-on resource's PID, when it has one.
/// * [targetName] - The target's display name at the time of the action (survives the target's deletion). 
/// * [detail] - Action-specific structure: what changed, from what, to what. Shapes are stable per action but may grow fields. 
/// * [createdAt] - When the action happened.
@BuiltValue()
abstract class AuditEvent implements Built<AuditEvent, AuditEventBuilder> {
  /// Opaque event id, unique and time-ordered.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// The acting user's PID; absent for server-initiated actions (scheduled jobs, startup restore). 
  @BuiltValueField(wireName: r'actorId')
  String? get actorId;

  /// The acting username at the time of the action (kept verbatim if the account is later renamed or deleted). 
  @BuiltValueField(wireName: r'actorName')
  String? get actorName;

  /// Dotted action name, resource first: `user.create`, `user.update`, `user.delete`, `user.approve`, `user.reject`, `invite.create`, `invite.revoke`, `playlist.delete`, `items.delete`, `entity.merge`, `trash.restore`, `trash.empty`, `backup.create`, `backup.delete`, `restore.stage`, `restore.apply`, `settings.update`, `schedule.update`, `library.create`, `library.read-only`, `transcoding.update`, `migration.run`, and more as surfaces grow. Open vocabulary; filter by prefix. 
  @BuiltValueField(wireName: r'action')
  String get action;

  /// What kind of thing was acted on (`user`, `playlist`, ...).
  @BuiltValueField(wireName: r'targetKind')
  String? get targetKind;

  /// The acted-on resource's PID, when it has one.
  @BuiltValueField(wireName: r'targetPid')
  String? get targetPid;

  /// The target's display name at the time of the action (survives the target's deletion). 
  @BuiltValueField(wireName: r'targetName')
  String? get targetName;

  /// Action-specific structure: what changed, from what, to what. Shapes are stable per action but may grow fields. 
  @BuiltValueField(wireName: r'detail')
  BuiltMap<String, JsonObject?>? get detail;

  /// When the action happened.
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  AuditEvent._();

  factory AuditEvent([void updates(AuditEventBuilder b)]) = _$AuditEvent;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AuditEventBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AuditEvent> get serializer => _$AuditEventSerializer();
}

class _$AuditEventSerializer implements PrimitiveSerializer<AuditEvent> {
  @override
  final Iterable<Type> types = const [AuditEvent, _$AuditEvent];

  @override
  final String wireName = r'AuditEvent';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AuditEvent object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    if (object.actorId != null) {
      yield r'actorId';
      yield serializers.serialize(
        object.actorId,
        specifiedType: const FullType(String),
      );
    }
    if (object.actorName != null) {
      yield r'actorName';
      yield serializers.serialize(
        object.actorName,
        specifiedType: const FullType(String),
      );
    }
    yield r'action';
    yield serializers.serialize(
      object.action,
      specifiedType: const FullType(String),
    );
    if (object.targetKind != null) {
      yield r'targetKind';
      yield serializers.serialize(
        object.targetKind,
        specifiedType: const FullType(String),
      );
    }
    if (object.targetPid != null) {
      yield r'targetPid';
      yield serializers.serialize(
        object.targetPid,
        specifiedType: const FullType(String),
      );
    }
    if (object.targetName != null) {
      yield r'targetName';
      yield serializers.serialize(
        object.targetName,
        specifiedType: const FullType(String),
      );
    }
    if (object.detail != null) {
      yield r'detail';
      yield serializers.serialize(
        object.detail,
        specifiedType: const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
      );
    }
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AuditEvent object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AuditEventBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'actorId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.actorId = valueDes;
          break;
        case r'actorName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.actorName = valueDes;
          break;
        case r'action':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.action = valueDes;
          break;
        case r'targetKind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.targetKind = valueDes;
          break;
        case r'targetPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.targetPid = valueDes;
          break;
        case r'targetName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.targetName = valueDes;
          break;
        case r'detail':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
          ) as BuiltMap<String, JsonObject?>;
          result.detail.replace(valueDes);
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AuditEvent deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AuditEventBuilder();
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

