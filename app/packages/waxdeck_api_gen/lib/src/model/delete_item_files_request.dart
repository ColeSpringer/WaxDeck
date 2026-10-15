//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'delete_item_files_request.g.dart';

/// A deletion (or a dry-run plan) of some of one item's files.
///
/// Properties:
/// * [filePids] - The files to delete, as getItemFiles names them.
/// * [mode] - `trash` is reversible from the trash surface; `permanent` bypasses it (administrators only). 
/// * [dryRun] - Answer the plan without deleting.
@BuiltValue()
abstract class DeleteItemFilesRequest implements Built<DeleteItemFilesRequest, DeleteItemFilesRequestBuilder> {
  /// The files to delete, as getItemFiles names them.
  @BuiltValueField(wireName: r'filePids')
  BuiltList<String> get filePids;

  /// `trash` is reversible from the trash surface; `permanent` bypasses it (administrators only). 
  @BuiltValueField(wireName: r'mode')
  DeleteItemFilesRequestModeEnum? get mode;
  // enum modeEnum {  trash,  permanent,  };

  /// Answer the plan without deleting.
  @BuiltValueField(wireName: r'dryRun')
  bool? get dryRun;

  DeleteItemFilesRequest._();

  factory DeleteItemFilesRequest([void updates(DeleteItemFilesRequestBuilder b)]) = _$DeleteItemFilesRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DeleteItemFilesRequestBuilder b) => b
      ..mode = DeleteItemFilesRequestModeEnum.valueOf('trash')
      ..dryRun = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<DeleteItemFilesRequest> get serializer => _$DeleteItemFilesRequestSerializer();
}

class _$DeleteItemFilesRequestSerializer implements PrimitiveSerializer<DeleteItemFilesRequest> {
  @override
  final Iterable<Type> types = const [DeleteItemFilesRequest, _$DeleteItemFilesRequest];

  @override
  final String wireName = r'DeleteItemFilesRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DeleteItemFilesRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'filePids';
    yield serializers.serialize(
      object.filePids,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    if (object.mode != null) {
      yield r'mode';
      yield serializers.serialize(
        object.mode,
        specifiedType: const FullType(DeleteItemFilesRequestModeEnum),
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
    DeleteItemFilesRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DeleteItemFilesRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'filePids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.filePids.replace(valueDes);
          break;
        case r'mode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DeleteItemFilesRequestModeEnum),
          ) as DeleteItemFilesRequestModeEnum?;
          if (valueDes == null) continue;
          result.mode = valueDes;
          break;
        case r'dryRun':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
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
  DeleteItemFilesRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DeleteItemFilesRequestBuilder();
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


/// `trash` is reversible from the trash surface; `permanent` bypasses it (administrators only). 
class DeleteItemFilesRequestModeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'trash')
  static const DeleteItemFilesRequestModeEnum trash = _$deleteItemFilesRequestModeEnum_trash;
  @BuiltValueEnumConst(wireName: r'permanent')
  static const DeleteItemFilesRequestModeEnum permanent = _$deleteItemFilesRequestModeEnum_permanent;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const DeleteItemFilesRequestModeEnum unknownDefaultOpenApi = _$deleteItemFilesRequestModeEnum_unknownDefaultOpenApi;

  static Serializer<DeleteItemFilesRequestModeEnum> get serializer => _$deleteItemFilesRequestModeEnumSerializer;

  const DeleteItemFilesRequestModeEnum._(String name): super(name);

  static BuiltSet<DeleteItemFilesRequestModeEnum> get values => _$deleteItemFilesRequestModeEnumValues;
  static DeleteItemFilesRequestModeEnum valueOf(String name) => _$deleteItemFilesRequestModeEnumValueOf(name);
}

