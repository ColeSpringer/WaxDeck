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
/// * [backupKeepCount] - How many backup archives to keep; older ones are deleted after each successful backup. 0 keeps every archive. 
/// * [backupKeepBytes] - Total archive bytes to keep, oldest deleted first when exceeded. 0 is unlimited. Imported archives are exempt. 
@BuiltValue()
abstract class AdminSettings implements Built<AdminSettings, AdminSettingsBuilder> {
  /// Whether open self-serve signup is accepted (registrations land pending). Invite links work regardless. 
  @BuiltValueField(wireName: r'signupEnabled')
  bool get signupEnabled;

  /// Server-wide read-only mode: every library behaves read-only (uploads, organizing, write-back, deletion, and the file tools are refused with code `read-only`). 
  @BuiltValueField(wireName: r'readOnly')
  bool get readOnly;

  /// How many backup archives to keep; older ones are deleted after each successful backup. 0 keeps every archive. 
  @BuiltValueField(wireName: r'backupKeepCount')
  int get backupKeepCount;

  /// Total archive bytes to keep, oldest deleted first when exceeded. 0 is unlimited. Imported archives are exempt. 
  @BuiltValueField(wireName: r'backupKeepBytes')
  int get backupKeepBytes;

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

