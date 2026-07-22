//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'delete_plan_entry.g.dart';

/// One item's part of a deletion.
///
/// Properties:
/// * [pid] - The item.
/// * [name] - Display name.
/// * [files] - Files deleted (or to delete).
/// * [bytes] - Bytes reclaimed (or to reclaim).
@BuiltValue()
abstract class DeletePlanEntry implements Built<DeletePlanEntry, DeletePlanEntryBuilder> {
  /// The item.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Display name.
  @BuiltValueField(wireName: r'name')
  String? get name;

  /// Files deleted (or to delete).
  @BuiltValueField(wireName: r'files')
  int get files;

  /// Bytes reclaimed (or to reclaim).
  @BuiltValueField(wireName: r'bytes')
  int get bytes;

  DeletePlanEntry._();

  factory DeletePlanEntry([void updates(DeletePlanEntryBuilder b)]) = _$DeletePlanEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DeletePlanEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DeletePlanEntry> get serializer => _$DeletePlanEntrySerializer();
}

class _$DeletePlanEntrySerializer implements PrimitiveSerializer<DeletePlanEntry> {
  @override
  final Iterable<Type> types = const [DeletePlanEntry, _$DeletePlanEntry];

  @override
  final String wireName = r'DeletePlanEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DeletePlanEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType(String),
      );
    }
    yield r'files';
    yield serializers.serialize(
      object.files,
      specifiedType: const FullType(int),
    );
    yield r'bytes';
    yield serializers.serialize(
      object.bytes,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DeletePlanEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DeletePlanEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'files':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.files = valueDes;
          break;
        case r'bytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.bytes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DeletePlanEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DeletePlanEntryBuilder();
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

