//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_settings_change.g.dart';

/// A write of runtime settings. Every field is optional, and a field left out keeps its stored value. 
///
/// Properties:
/// * [signupEnabled] - Whether open self-serve signup is accepted (registrations land pending). Invite links work regardless. 
/// * [readOnly] - Server-wide read-only mode: every library behaves read-only (uploads, organizing, write-back, deletion, and the file tools are refused with code `read-only`). 
/// * [sonicAnalysis] - Whether the server analyzes its own library for sonic similarity in the background. Applies immediately; turning it off mid-library keeps the embeddings already computed. 
/// * [enrichmentWriteTags] - Whether enrichment writes what it filled into the files (turning it on catches earlier values up; a read-only server writes nothing). 
/// * [radioExternalArt] - Whether radio may look a station's announced title up externally when nothing in this library matches it. Turning it off drops what it fetched and makes no outbound request. 
/// * [backupKeepCount] - How many backup archives to keep; older ones are deleted after each successful backup. 0 keeps every archive. 
/// * [backupKeepBytes] - Total archive bytes to keep, oldest deleted first when exceeded. 0 is unlimited. Imported archives are exempt. 
/// * [trashRetentionDays] - Automatically purge trashed files older than this many days on a periodic sweep; 0 disables retention. 
/// * [taskRetentionDays] - Clear finished tool tasks older than this many days on the scheduled prune, and drop the Organizer's journal of runs older than this; 0 keeps both. 
@BuiltValue()
abstract class AdminSettingsChange implements Built<AdminSettingsChange, AdminSettingsChangeBuilder> {
  /// Whether open self-serve signup is accepted (registrations land pending). Invite links work regardless. 
  @BuiltValueField(wireName: r'signupEnabled')
  bool? get signupEnabled;

  /// Server-wide read-only mode: every library behaves read-only (uploads, organizing, write-back, deletion, and the file tools are refused with code `read-only`). 
  @BuiltValueField(wireName: r'readOnly')
  bool? get readOnly;

  /// Whether the server analyzes its own library for sonic similarity in the background. Applies immediately; turning it off mid-library keeps the embeddings already computed. 
  @BuiltValueField(wireName: r'sonicAnalysis')
  bool? get sonicAnalysis;

  /// Whether enrichment writes what it filled into the files (turning it on catches earlier values up; a read-only server writes nothing). 
  @BuiltValueField(wireName: r'enrichmentWriteTags')
  bool? get enrichmentWriteTags;

  /// Whether radio may look a station's announced title up externally when nothing in this library matches it. Turning it off drops what it fetched and makes no outbound request. 
  @BuiltValueField(wireName: r'radioExternalArt')
  bool? get radioExternalArt;

  /// How many backup archives to keep; older ones are deleted after each successful backup. 0 keeps every archive. 
  @BuiltValueField(wireName: r'backupKeepCount')
  int? get backupKeepCount;

  /// Total archive bytes to keep, oldest deleted first when exceeded. 0 is unlimited. Imported archives are exempt. 
  @BuiltValueField(wireName: r'backupKeepBytes')
  int? get backupKeepBytes;

  /// Automatically purge trashed files older than this many days on a periodic sweep; 0 disables retention. 
  @BuiltValueField(wireName: r'trashRetentionDays')
  int? get trashRetentionDays;

  /// Clear finished tool tasks older than this many days on the scheduled prune, and drop the Organizer's journal of runs older than this; 0 keeps both. 
  @BuiltValueField(wireName: r'taskRetentionDays')
  int? get taskRetentionDays;

  AdminSettingsChange._();

  factory AdminSettingsChange([void updates(AdminSettingsChangeBuilder b)]) = _$AdminSettingsChange;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminSettingsChangeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminSettingsChange> get serializer => _$AdminSettingsChangeSerializer();
}

class _$AdminSettingsChangeSerializer implements PrimitiveSerializer<AdminSettingsChange> {
  @override
  final Iterable<Type> types = const [AdminSettingsChange, _$AdminSettingsChange];

  @override
  final String wireName = r'AdminSettingsChange';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminSettingsChange object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.signupEnabled != null) {
      yield r'signupEnabled';
      yield serializers.serialize(
        object.signupEnabled,
        specifiedType: const FullType(bool),
      );
    }
    if (object.readOnly != null) {
      yield r'readOnly';
      yield serializers.serialize(
        object.readOnly,
        specifiedType: const FullType(bool),
      );
    }
    if (object.sonicAnalysis != null) {
      yield r'sonicAnalysis';
      yield serializers.serialize(
        object.sonicAnalysis,
        specifiedType: const FullType(bool),
      );
    }
    if (object.enrichmentWriteTags != null) {
      yield r'enrichmentWriteTags';
      yield serializers.serialize(
        object.enrichmentWriteTags,
        specifiedType: const FullType(bool),
      );
    }
    if (object.radioExternalArt != null) {
      yield r'radioExternalArt';
      yield serializers.serialize(
        object.radioExternalArt,
        specifiedType: const FullType(bool),
      );
    }
    if (object.backupKeepCount != null) {
      yield r'backupKeepCount';
      yield serializers.serialize(
        object.backupKeepCount,
        specifiedType: const FullType(int),
      );
    }
    if (object.backupKeepBytes != null) {
      yield r'backupKeepBytes';
      yield serializers.serialize(
        object.backupKeepBytes,
        specifiedType: const FullType(int),
      );
    }
    if (object.trashRetentionDays != null) {
      yield r'trashRetentionDays';
      yield serializers.serialize(
        object.trashRetentionDays,
        specifiedType: const FullType(int),
      );
    }
    if (object.taskRetentionDays != null) {
      yield r'taskRetentionDays';
      yield serializers.serialize(
        object.taskRetentionDays,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AdminSettingsChange object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminSettingsChangeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'signupEnabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.signupEnabled = valueDes;
          break;
        case r'readOnly':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.readOnly = valueDes;
          break;
        case r'sonicAnalysis':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.sonicAnalysis = valueDes;
          break;
        case r'enrichmentWriteTags':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.enrichmentWriteTags = valueDes;
          break;
        case r'radioExternalArt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.radioExternalArt = valueDes;
          break;
        case r'backupKeepCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.backupKeepCount = valueDes;
          break;
        case r'backupKeepBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.backupKeepBytes = valueDes;
          break;
        case r'trashRetentionDays':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.trashRetentionDays = valueDes;
          break;
        case r'taskRetentionDays':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.taskRetentionDays = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AdminSettingsChange deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminSettingsChangeBuilder();
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


