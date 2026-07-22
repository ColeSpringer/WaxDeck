//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'delete_items_request.g.dart';

/// A deletion (or a dry-run plan) over library items.
///
/// Properties:
/// * [pids] - The items whose files to delete.
/// * [mode] - `trash` is reversible from the trash surface; `permanent` bypasses it (administrators only). 
/// * [dryRun] - Answer the plan without deleting.
@BuiltValue()
abstract class DeleteItemsRequest implements Built<DeleteItemsRequest, DeleteItemsRequestBuilder> {
  /// The items whose files to delete.
  @BuiltValueField(wireName: r'pids')
  BuiltList<String> get pids;

  /// `trash` is reversible from the trash surface; `permanent` bypasses it (administrators only). 
  @BuiltValueField(wireName: r'mode')
  DeleteItemsRequestModeEnum? get mode;
  // enum modeEnum {  trash,  permanent,  };

  /// Answer the plan without deleting.
  @BuiltValueField(wireName: r'dryRun')
  bool? get dryRun;

  DeleteItemsRequest._();

  factory DeleteItemsRequest([void updates(DeleteItemsRequestBuilder b)]) = _$DeleteItemsRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DeleteItemsRequestBuilder b) => b
      ..mode = const DeleteItemsRequestModeEnum._('trash')
      ..dryRun = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<DeleteItemsRequest> get serializer => _$DeleteItemsRequestSerializer();
}

class _$DeleteItemsRequestSerializer implements PrimitiveSerializer<DeleteItemsRequest> {
  @override
  final Iterable<Type> types = const [DeleteItemsRequest, _$DeleteItemsRequest];

  @override
  final String wireName = r'DeleteItemsRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DeleteItemsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pids';
    yield serializers.serialize(
      object.pids,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    if (object.mode != null) {
      yield r'mode';
      yield serializers.serialize(
        object.mode,
        specifiedType: const FullType(DeleteItemsRequestModeEnum),
      );
    }
    if (object.dryRun != null) {
      yield r'dryRun';
      yield serializers.serialize(
        object.dryRun,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DeleteItemsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DeleteItemsRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.pids.replace(valueDes);
          break;
        case r'mode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DeleteItemsRequestModeEnum),
          ) as DeleteItemsRequestModeEnum;
          result.mode = valueDes;
          break;
        case r'dryRun':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.dryRun = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DeleteItemsRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DeleteItemsRequestBuilder();
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

class DeleteItemsRequestModeEnum extends EnumClass {

  /// `trash` is reversible from the trash surface; `permanent` bypasses it (administrators only). 
  @BuiltValueEnumConst(wireName: r'trash')
  static const DeleteItemsRequestModeEnum trash = _$deleteItemsRequestModeEnum_trash;
  /// `trash` is reversible from the trash surface; `permanent` bypasses it (administrators only). 
  @BuiltValueEnumConst(wireName: r'permanent')
  static const DeleteItemsRequestModeEnum permanent = _$deleteItemsRequestModeEnum_permanent;

  static Serializer<DeleteItemsRequestModeEnum> get serializer => _$deleteItemsRequestModeEnumSerializer;

  const DeleteItemsRequestModeEnum._(String name): super(name);

  static BuiltSet<DeleteItemsRequestModeEnum> get values => _$deleteItemsRequestModeEnumValues;
  static DeleteItemsRequestModeEnum valueOf(String name) => _$deleteItemsRequestModeEnumValueOf(name);
}

