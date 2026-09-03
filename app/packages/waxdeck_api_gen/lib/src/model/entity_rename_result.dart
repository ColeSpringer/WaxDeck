//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/write_back_failure.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'entity_rename_result.g.dart';

/// What a rename did. The catalog write succeeded whenever this shape returns; write-back trouble rides along in `failures` instead of failing the rename. 
///
/// Properties:
/// * [entityPid] - The renamed entity. Unchanged from the request, since the row survives; on `merged` the row is gone and `mergedInto` names where it went. 
/// * [outcome] - What the rename did to the entity's identity key.
/// * [mergedInto] - The surviving entity when `outcome` is `merged`. Present only then. 
/// * [movedAlbums] - Albums that came out under a different release group than they went in under, which an album rename can do when the new anchor or title implies a group the album was not in. 
/// * [members] - How many items carried the rename.
/// * [credits] - How many contributor-role credits (producer, composer, narrator, translator, editor) moved with an artist rename. An item can be counted in both `members` and here. 
/// * [failures] - Files whose tags could not be updated.
@BuiltValue()
abstract class EntityRenameResult implements Built<EntityRenameResult, EntityRenameResultBuilder> {
  /// The renamed entity. Unchanged from the request, since the row survives; on `merged` the row is gone and `mergedInto` names where it went. 
  @BuiltValueField(wireName: r'entityPid')
  String get entityPid;

  /// What the rename did to the entity's identity key.
  @BuiltValueField(wireName: r'outcome')
  EntityRenameResultOutcomeEnum get outcome;
  // enum outcomeEnum {  renamed,  merged,  refreshed,  };

  /// The surviving entity when `outcome` is `merged`. Present only then. 
  @BuiltValueField(wireName: r'mergedInto')
  String? get mergedInto;

  /// Albums that came out under a different release group than they went in under, which an album rename can do when the new anchor or title implies a group the album was not in. 
  @BuiltValueField(wireName: r'movedAlbums')
  BuiltList<String>? get movedAlbums;

  /// How many items carried the rename.
  @BuiltValueField(wireName: r'members')
  int get members;

  /// How many contributor-role credits (producer, composer, narrator, translator, editor) moved with an artist rename. An item can be counted in both `members` and here. 
  @BuiltValueField(wireName: r'credits')
  int get credits;

  /// Files whose tags could not be updated.
  @BuiltValueField(wireName: r'failures')
  BuiltList<WriteBackFailure>? get failures;

  EntityRenameResult._();

  factory EntityRenameResult([void updates(EntityRenameResultBuilder b)]) = _$EntityRenameResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EntityRenameResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EntityRenameResult> get serializer => _$EntityRenameResultSerializer();
}

class _$EntityRenameResultSerializer implements PrimitiveSerializer<EntityRenameResult> {
  @override
  final Iterable<Type> types = const [EntityRenameResult, _$EntityRenameResult];

  @override
  final String wireName = r'EntityRenameResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EntityRenameResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entityPid';
    yield serializers.serialize(
      object.entityPid,
      specifiedType: const FullType(String),
    );
    yield r'outcome';
    yield serializers.serialize(
      object.outcome,
      specifiedType: const FullType(EntityRenameResultOutcomeEnum),
    );
    if (object.mergedInto != null) {
      yield r'mergedInto';
      yield serializers.serialize(
        object.mergedInto,
        specifiedType: const FullType(String),
      );
    }
    if (object.movedAlbums != null) {
      yield r'movedAlbums';
      yield serializers.serialize(
        object.movedAlbums,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    yield r'members';
    yield serializers.serialize(
      object.members,
      specifiedType: const FullType(int),
    );
    yield r'credits';
    yield serializers.serialize(
      object.credits,
      specifiedType: const FullType(int),
    );
    if (object.failures != null) {
      yield r'failures';
      yield serializers.serialize(
        object.failures,
        specifiedType: const FullType(BuiltList, [FullType(WriteBackFailure)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EntityRenameResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EntityRenameResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entityPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.entityPid = valueDes;
          break;
        case r'outcome':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(EntityRenameResultOutcomeEnum),
          ) as EntityRenameResultOutcomeEnum;
          result.outcome = valueDes;
          break;
        case r'mergedInto':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.mergedInto = valueDes;
          break;
        case r'movedAlbums':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.movedAlbums.replace(valueDes);
          break;
        case r'members':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.members = valueDes;
          break;
        case r'credits':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.credits = valueDes;
          break;
        case r'failures':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(WriteBackFailure)]),
          ) as BuiltList<WriteBackFailure>;
          result.failures.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EntityRenameResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EntityRenameResultBuilder();
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

class EntityRenameResultOutcomeEnum extends EnumClass {

  /// What the rename did to the entity's identity key.
  @BuiltValueEnumConst(wireName: r'renamed')
  static const EntityRenameResultOutcomeEnum renamed = _$entityRenameResultOutcomeEnum_renamed;
  /// What the rename did to the entity's identity key.
  @BuiltValueEnumConst(wireName: r'merged')
  static const EntityRenameResultOutcomeEnum merged = _$entityRenameResultOutcomeEnum_merged;
  /// What the rename did to the entity's identity key.
  @BuiltValueEnumConst(wireName: r'refreshed')
  static const EntityRenameResultOutcomeEnum refreshed = _$entityRenameResultOutcomeEnum_refreshed;
  /// What the rename did to the entity's identity key.
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const EntityRenameResultOutcomeEnum unknownDefaultOpenApi = _$entityRenameResultOutcomeEnum_unknownDefaultOpenApi;

  static Serializer<EntityRenameResultOutcomeEnum> get serializer => _$entityRenameResultOutcomeEnumSerializer;

  const EntityRenameResultOutcomeEnum._(String name): super(name);

  static BuiltSet<EntityRenameResultOutcomeEnum> get values => _$entityRenameResultOutcomeEnumValues;
  static EntityRenameResultOutcomeEnum valueOf(String name) => _$entityRenameResultOutcomeEnumValueOf(name);
}

