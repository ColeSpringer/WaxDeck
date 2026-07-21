//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/duplicate_entity.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'duplicate_group.g.dart';

/// One duplicate finding.
///
/// Properties:
/// * [entityType] - `artist`, `album`, `release-group`, or `genre`.
/// * [survivor] 
/// * [losers] - The suggested merge losers.
/// * [detail] - The audit's explanation of the finding.
@BuiltValue()
abstract class DuplicateGroup implements Built<DuplicateGroup, DuplicateGroupBuilder> {
  /// `artist`, `album`, `release-group`, or `genre`.
  @BuiltValueField(wireName: r'entityType')
  String get entityType;

  @BuiltValueField(wireName: r'survivor')
  DuplicateEntity get survivor;

  /// The suggested merge losers.
  @BuiltValueField(wireName: r'losers')
  BuiltList<DuplicateEntity> get losers;

  /// The audit's explanation of the finding.
  @BuiltValueField(wireName: r'detail')
  String? get detail;

  DuplicateGroup._();

  factory DuplicateGroup([void updates(DuplicateGroupBuilder b)]) = _$DuplicateGroup;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DuplicateGroupBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DuplicateGroup> get serializer => _$DuplicateGroupSerializer();
}

class _$DuplicateGroupSerializer implements PrimitiveSerializer<DuplicateGroup> {
  @override
  final Iterable<Type> types = const [DuplicateGroup, _$DuplicateGroup];

  @override
  final String wireName = r'DuplicateGroup';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DuplicateGroup object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entityType';
    yield serializers.serialize(
      object.entityType,
      specifiedType: const FullType(String),
    );
    yield r'survivor';
    yield serializers.serialize(
      object.survivor,
      specifiedType: const FullType(DuplicateEntity),
    );
    yield r'losers';
    yield serializers.serialize(
      object.losers,
      specifiedType: const FullType(BuiltList, [FullType(DuplicateEntity)]),
    );
    if (object.detail != null) {
      yield r'detail';
      yield serializers.serialize(
        object.detail,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DuplicateGroup object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DuplicateGroupBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entityType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.entityType = valueDes;
          break;
        case r'survivor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DuplicateEntity),
          ) as DuplicateEntity;
          result.survivor.replace(valueDes);
          break;
        case r'losers':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(DuplicateEntity)]),
          ) as BuiltList<DuplicateEntity>;
          result.losers.replace(valueDes);
          break;
        case r'detail':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.detail = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DuplicateGroup deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DuplicateGroupBuilder();
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

