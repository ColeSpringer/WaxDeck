//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'backup.g.dart';

/// One backup archive.
///
/// Properties:
/// * [id] - Backup PID.
/// * [state] - `running`, `done`, or `failed`. A string, not a closed enum. 
/// * [trigger] - What produced it: `manual`, `scheduled`, or `imported`. A string, not a closed enum. 
/// * [fileName] - Archive file name.
/// * [sizeBytes] - Archive size once written.
/// * [error] - Why the backup failed, when `failed`.
/// * [createdAt] - When the backup started (or was imported).
/// * [finishedAt] - When it reached a terminal state.
@BuiltValue()
abstract class Backup implements Built<Backup, BackupBuilder> {
  /// Backup PID.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// `running`, `done`, or `failed`. A string, not a closed enum. 
  @BuiltValueField(wireName: r'state')
  String get state;

  /// What produced it: `manual`, `scheduled`, or `imported`. A string, not a closed enum. 
  @BuiltValueField(wireName: r'trigger')
  String get trigger;

  /// Archive file name.
  @BuiltValueField(wireName: r'fileName')
  String get fileName;

  /// Archive size once written.
  @BuiltValueField(wireName: r'sizeBytes')
  int? get sizeBytes;

  /// Why the backup failed, when `failed`.
  @BuiltValueField(wireName: r'error')
  String? get error;

  /// When the backup started (or was imported).
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  /// When it reached a terminal state.
  @BuiltValueField(wireName: r'finishedAt')
  DateTime? get finishedAt;

  Backup._();

  factory Backup([void updates(BackupBuilder b)]) = _$Backup;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BackupBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Backup> get serializer => _$BackupSerializer();
}

class _$BackupSerializer implements PrimitiveSerializer<Backup> {
  @override
  final Iterable<Type> types = const [Backup, _$Backup];

  @override
  final String wireName = r'Backup';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Backup object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'state';
    yield serializers.serialize(
      object.state,
      specifiedType: const FullType(String),
    );
    yield r'trigger';
    yield serializers.serialize(
      object.trigger,
      specifiedType: const FullType(String),
    );
    yield r'fileName';
    yield serializers.serialize(
      object.fileName,
      specifiedType: const FullType(String),
    );
    if (object.sizeBytes != null) {
      yield r'sizeBytes';
      yield serializers.serialize(
        object.sizeBytes,
        specifiedType: const FullType(int),
      );
    }
    if (object.error != null) {
      yield r'error';
      yield serializers.serialize(
        object.error,
        specifiedType: const FullType(String),
      );
    }
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.finishedAt != null) {
      yield r'finishedAt';
      yield serializers.serialize(
        object.finishedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Backup object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BackupBuilder result,
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
        case r'state':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.state = valueDes;
          break;
        case r'trigger':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.trigger = valueDes;
          break;
        case r'fileName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fileName = valueDes;
          break;
        case r'sizeBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sizeBytes = valueDes;
          break;
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.error = valueDes;
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'finishedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.finishedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Backup deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BackupBuilder();
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

