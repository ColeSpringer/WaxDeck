//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_settings.g.dart';

/// Runtime-editable server settings.
///
/// Properties:
/// * [signupEnabled] - Whether open self-serve signup is accepted (registrations land pending). Invite links work regardless. 
/// * [readOnly] - Server-wide read-only mode: every library behaves read-only (uploads, organizing, write-back, deletion, and the file tools are refused with code `read-only`). 
/// * [sonicAnalysis] - Whether the server analyzes its own library for sonic similarity in the background (the embedded analyzer). Applies immediately; turning it off mid-library keeps the embeddings already computed. The boot default comes from `WAXDECK_SONIC_ANALYSIS`, and this setting overrides it once saved. External workers are unaffected (their access is the worker-token configuration). Optional on PUT so settings writers predating this field never change it: absent keeps the current value. Always present in responses. 
/// * [enrichmentWriteTags] - Whether the whole-library enrichment pass writes what it filled back into the files, which is what makes enrichment survive a rescan: the catalog is authoritative either way, but a rescan re-reads the tags and would otherwise clear values only the catalog held.  Off by default, because it modifies the listener's own files. Files whose format cannot store a key are counted in `enrichmentStatus.lastRun.tagsUnrepresented` and left byte-identical, which is not a failure. Applies to the next pass; a run already in flight keeps the setting it started under. Optional on PUT so settings writers predating this field never change it: absent keeps the current value. Always present in responses. 
/// * [backupKeepCount] - How many backup archives to keep; older ones are deleted after each successful backup. 0 keeps every archive. 
/// * [backupKeepBytes] - Total archive bytes to keep, oldest deleted first when exceeded. 0 is unlimited. Imported archives are exempt. 
/// * [trashRetentionDays] - Automatically purge trashed files older than this many days on a periodic sweep; 0 disables retention (the trash keeps entries until an administrator empties it). Optional on PUT so settings writers predating this field never change it: absent keeps the current value. Always present in responses. 
/// * [taskRetentionDays] - Clear finished tool tasks older than this many days on the scheduled prune; terminal rows only. 0 keeps them, and an unconfigured server answers 30 - so unlike `trashRetentionDays`, 0 here is a choice rather than the default. Optional on PUT (absent keeps the current value), always present in responses. 
@BuiltValue()
abstract class AdminSettings implements Built<AdminSettings, AdminSettingsBuilder> {
  /// Whether open self-serve signup is accepted (registrations land pending). Invite links work regardless. 
  @BuiltValueField(wireName: r'signupEnabled')
  bool get signupEnabled;

  /// Server-wide read-only mode: every library behaves read-only (uploads, organizing, write-back, deletion, and the file tools are refused with code `read-only`). 
  @BuiltValueField(wireName: r'readOnly')
  bool get readOnly;

  /// Whether the server analyzes its own library for sonic similarity in the background (the embedded analyzer). Applies immediately; turning it off mid-library keeps the embeddings already computed. The boot default comes from `WAXDECK_SONIC_ANALYSIS`, and this setting overrides it once saved. External workers are unaffected (their access is the worker-token configuration). Optional on PUT so settings writers predating this field never change it: absent keeps the current value. Always present in responses. 
  @BuiltValueField(wireName: r'sonicAnalysis')
  bool? get sonicAnalysis;

  /// Whether the whole-library enrichment pass writes what it filled back into the files, which is what makes enrichment survive a rescan: the catalog is authoritative either way, but a rescan re-reads the tags and would otherwise clear values only the catalog held.  Off by default, because it modifies the listener's own files. Files whose format cannot store a key are counted in `enrichmentStatus.lastRun.tagsUnrepresented` and left byte-identical, which is not a failure. Applies to the next pass; a run already in flight keeps the setting it started under. Optional on PUT so settings writers predating this field never change it: absent keeps the current value. Always present in responses. 
  @BuiltValueField(wireName: r'enrichmentWriteTags')
  bool? get enrichmentWriteTags;

  /// How many backup archives to keep; older ones are deleted after each successful backup. 0 keeps every archive. 
  @BuiltValueField(wireName: r'backupKeepCount')
  int get backupKeepCount;

  /// Total archive bytes to keep, oldest deleted first when exceeded. 0 is unlimited. Imported archives are exempt. 
  @BuiltValueField(wireName: r'backupKeepBytes')
  int get backupKeepBytes;

  /// Automatically purge trashed files older than this many days on a periodic sweep; 0 disables retention (the trash keeps entries until an administrator empties it). Optional on PUT so settings writers predating this field never change it: absent keeps the current value. Always present in responses. 
  @BuiltValueField(wireName: r'trashRetentionDays')
  int? get trashRetentionDays;

  /// Clear finished tool tasks older than this many days on the scheduled prune; terminal rows only. 0 keeps them, and an unconfigured server answers 30 - so unlike `trashRetentionDays`, 0 here is a choice rather than the default. Optional on PUT (absent keeps the current value), always present in responses. 
  @BuiltValueField(wireName: r'taskRetentionDays')
  int? get taskRetentionDays;

  AdminSettings._();

  factory AdminSettings([void updates(AdminSettingsBuilder b)]) = _$AdminSettings;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminSettingsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminSettings> get serializer => _$AdminSettingsSerializer();
}

class _$AdminSettingsSerializer implements PrimitiveSerializer<AdminSettings> {
  @override
  final Iterable<Type> types = const [AdminSettings, _$AdminSettings];

  @override
  final String wireName = r'AdminSettings';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminSettings object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'signupEnabled';
    yield serializers.serialize(
      object.signupEnabled,
      specifiedType: const FullType(bool),
    );
    yield r'readOnly';
    yield serializers.serialize(
      object.readOnly,
      specifiedType: const FullType(bool),
    );
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
    yield r'backupKeepCount';
    yield serializers.serialize(
      object.backupKeepCount,
      specifiedType: const FullType(int),
    );
    yield r'backupKeepBytes';
    yield serializers.serialize(
      object.backupKeepBytes,
      specifiedType: const FullType(int),
    );
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
    AdminSettings object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminSettingsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'signupEnabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.signupEnabled = valueDes;
          break;
        case r'readOnly':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.readOnly = valueDes;
          break;
        case r'sonicAnalysis':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.sonicAnalysis = valueDes;
          break;
        case r'enrichmentWriteTags':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.enrichmentWriteTags = valueDes;
          break;
        case r'backupKeepCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.backupKeepCount = valueDes;
          break;
        case r'backupKeepBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.backupKeepBytes = valueDes;
          break;
        case r'trashRetentionDays':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.trashRetentionDays = valueDes;
          break;
        case r'taskRetentionDays':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
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
  AdminSettings deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminSettingsBuilder();
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

