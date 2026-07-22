//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/delete_plan_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'delete_items_result.g.dart';

/// What a deletion did, or would do.
///
/// Properties:
/// * [applied] - False for a dry run.
/// * [mode] - The mode that was (or would be) used.
/// * [entries] - Per-item breakdown.
@BuiltValue()
abstract class DeleteItemsResult implements Built<DeleteItemsResult, DeleteItemsResultBuilder> {
  /// False for a dry run.
  @BuiltValueField(wireName: r'applied')
  bool get applied;

  /// The mode that was (or would be) used.
  @BuiltValueField(wireName: r'mode')
  String get mode;

  /// Per-item breakdown.
  @BuiltValueField(wireName: r'entries')
  BuiltList<DeletePlanEntry> get entries;

  DeleteItemsResult._();

  factory DeleteItemsResult([void updates(DeleteItemsResultBuilder b)]) = _$DeleteItemsResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DeleteItemsResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DeleteItemsResult> get serializer => _$DeleteItemsResultSerializer();
}

class _$DeleteItemsResultSerializer implements PrimitiveSerializer<DeleteItemsResult> {
  @override
  final Iterable<Type> types = const [DeleteItemsResult, _$DeleteItemsResult];

  @override
  final String wireName = r'DeleteItemsResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DeleteItemsResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'applied';
    yield serializers.serialize(
      object.applied,
      specifiedType: const FullType(bool),
    );
    yield r'mode';
    yield serializers.serialize(
      object.mode,
      specifiedType: const FullType(String),
    );
    yield r'entries';
    yield serializers.serialize(
      object.entries,
      specifiedType: const FullType(BuiltList, [FullType(DeletePlanEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DeleteItemsResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DeleteItemsResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'applied':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.applied = valueDes;
          break;
        case r'mode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.mode = valueDes;
          break;
        case r'entries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(DeletePlanEntry)]),
          ) as BuiltList<DeletePlanEntry>;
          result.entries.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DeleteItemsResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DeleteItemsResultBuilder();
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

