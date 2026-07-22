//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'trash_entry.g.dart';

/// One file in the catalog's deletion undo journal.
///
/// Properties:
/// * [id] - Trash entry PID.
/// * [itemPid] - The item the file belonged to.
/// * [name] - The file's original library-relative path.
/// * [reason] - Why it was deleted: `user`, `prune`, or `permanent`. An open string. 
/// * [sizeBytes] - File size.
/// * [trashedAt] - When it was deleted.
/// * [restoredAt] - When it was restored; absent while trashed.
@BuiltValue()
abstract class TrashEntry implements Built<TrashEntry, TrashEntryBuilder> {
  /// Trash entry PID.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// The item the file belonged to.
  @BuiltValueField(wireName: r'itemPid')
  String? get itemPid;

  /// The file's original library-relative path.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Why it was deleted: `user`, `prune`, or `permanent`. An open string. 
  @BuiltValueField(wireName: r'reason')
  String get reason;

  /// File size.
  @BuiltValueField(wireName: r'sizeBytes')
  int get sizeBytes;

  /// When it was deleted.
  @BuiltValueField(wireName: r'trashedAt')
  DateTime get trashedAt;

  /// When it was restored; absent while trashed.
  @BuiltValueField(wireName: r'restoredAt')
  DateTime? get restoredAt;

  TrashEntry._();

  factory TrashEntry([void updates(TrashEntryBuilder b)]) = _$TrashEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TrashEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TrashEntry> get serializer => _$TrashEntrySerializer();
}

class _$TrashEntrySerializer implements PrimitiveSerializer<TrashEntry> {
  @override
  final Iterable<Type> types = const [TrashEntry, _$TrashEntry];

  @override
  final String wireName = r'TrashEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TrashEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    if (object.itemPid != null) {
      yield r'itemPid';
      yield serializers.serialize(
        object.itemPid,
        specifiedType: const FullType(String),
      );
    }
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'reason';
    yield serializers.serialize(
      object.reason,
      specifiedType: const FullType(String),
    );
    yield r'sizeBytes';
    yield serializers.serialize(
      object.sizeBytes,
      specifiedType: const FullType(int),
    );
    yield r'trashedAt';
    yield serializers.serialize(
      object.trashedAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.restoredAt != null) {
      yield r'restoredAt';
      yield serializers.serialize(
        object.restoredAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    TrashEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TrashEntryBuilder result,
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
        case r'itemPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.itemPid = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reason = valueDes;
          break;
        case r'sizeBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sizeBytes = valueDes;
          break;
        case r'trashedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.trashedAt = valueDes;
          break;
        case r'restoredAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.restoredAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TrashEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TrashEntryBuilder();
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

