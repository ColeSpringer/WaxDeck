//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/backup.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'backup_list.g.dart';

/// All backup archives.
///
/// Properties:
/// * [backups] - Backups, newest first.
@BuiltValue()
abstract class BackupList implements Built<BackupList, BackupListBuilder> {
  /// Backups, newest first.
  @BuiltValueField(wireName: r'backups')
  BuiltList<Backup> get backups;

  BackupList._();

  factory BackupList([void updates(BackupListBuilder b)]) = _$BackupList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BackupListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BackupList> get serializer => _$BackupListSerializer();
}

class _$BackupListSerializer implements PrimitiveSerializer<BackupList> {
  @override
  final Iterable<Type> types = const [BackupList, _$BackupList];

  @override
  final String wireName = r'BackupList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BackupList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'backups';
    yield serializers.serialize(
      object.backups,
      specifiedType: const FullType(BuiltList, [FullType(Backup)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    BackupList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BackupListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'backups':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Backup)]),
          ) as BuiltList<Backup>;
          result.backups.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BackupList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BackupListBuilder();
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

