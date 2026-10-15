//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'delete_plan_file.g.dart';

/// One file a deletion removes (or would remove).
///
/// Properties:
/// * [filePid] - The file, as getItemFiles names it.
/// * [name] - The file's name, without its folder.
/// * [sizeBytes] - The file's size in bytes, when it could be read.
/// * [role] - `primary`, `part` or `alternate`, as getItemFiles reports it; new roles may appear. 
@BuiltValue()
abstract class DeletePlanFile implements Built<DeletePlanFile, DeletePlanFileBuilder> {
  /// The file, as getItemFiles names it.
  @BuiltValueField(wireName: r'filePid')
  String get filePid;

  /// The file's name, without its folder.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// The file's size in bytes, when it could be read.
  @BuiltValueField(wireName: r'sizeBytes')
  int? get sizeBytes;

  /// `primary`, `part` or `alternate`, as getItemFiles reports it; new roles may appear. 
  @BuiltValueField(wireName: r'role')
  String get role;

  DeletePlanFile._();

  factory DeletePlanFile([void updates(DeletePlanFileBuilder b)]) = _$DeletePlanFile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DeletePlanFileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DeletePlanFile> get serializer => _$DeletePlanFileSerializer();
}

class _$DeletePlanFileSerializer implements PrimitiveSerializer<DeletePlanFile> {
  @override
  final Iterable<Type> types = const [DeletePlanFile, _$DeletePlanFile];

  @override
  final String wireName = r'DeletePlanFile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DeletePlanFile object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'filePid';
    yield serializers.serialize(
      object.filePid,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.sizeBytes != null) {
      yield r'sizeBytes';
      yield serializers.serialize(
        object.sizeBytes,
        specifiedType: const FullType(int),
      );
    }
    yield r'role';
    yield serializers.serialize(
      object.role,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DeletePlanFile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DeletePlanFileBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'filePid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.filePid = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'sizeBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.sizeBytes = valueDes;
          break;
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.role = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DeletePlanFile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DeletePlanFileBuilder();
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


