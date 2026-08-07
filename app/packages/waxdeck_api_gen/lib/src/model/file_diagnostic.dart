//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'file_diagnostic.g.dart';

/// One persisted observation about a library file, keyed for display by its path (files are not a first-class API resource, so no file id is surfaced). 
///
/// Properties:
/// * [path] - The file's display path.
/// * [origin] - The writer that recorded it (`scan`, `organize`, `replaygain`, `edit`, or `enrichment`); new writers may appear. 
/// * [code] - What was observed (`unsupported_format`, `legacy_only_tags`, `lyrics_partial`, `sidecar_skipped`, `cue_track_dropped`, `tag_write_lost`, `tag_write_unsynced`, or `corrupt_audio`); new codes may appear, so treat an unknown value as a generic finding. 
/// * [severity] - `info`, `warn`, or `error`.
/// * [tagKey] - The tag key a key-specific diagnostic concerns, when any.
/// * [detail] - The writer's own note, when it carries one.
/// * [seenAt] - When the diagnostic was last recorded.
@BuiltValue()
abstract class FileDiagnostic implements Built<FileDiagnostic, FileDiagnosticBuilder> {
  /// The file's display path.
  @BuiltValueField(wireName: r'path')
  String get path;

  /// The writer that recorded it (`scan`, `organize`, `replaygain`, `edit`, or `enrichment`); new writers may appear. 
  @BuiltValueField(wireName: r'origin')
  String get origin;

  /// What was observed (`unsupported_format`, `legacy_only_tags`, `lyrics_partial`, `sidecar_skipped`, `cue_track_dropped`, `tag_write_lost`, `tag_write_unsynced`, or `corrupt_audio`); new codes may appear, so treat an unknown value as a generic finding. 
  @BuiltValueField(wireName: r'code')
  String get code;

  /// `info`, `warn`, or `error`.
  @BuiltValueField(wireName: r'severity')
  String get severity;

  /// The tag key a key-specific diagnostic concerns, when any.
  @BuiltValueField(wireName: r'tagKey')
  String? get tagKey;

  /// The writer's own note, when it carries one.
  @BuiltValueField(wireName: r'detail')
  String? get detail;

  /// When the diagnostic was last recorded.
  @BuiltValueField(wireName: r'seenAt')
  DateTime get seenAt;

  FileDiagnostic._();

  factory FileDiagnostic([void updates(FileDiagnosticBuilder b)]) = _$FileDiagnostic;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(FileDiagnosticBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<FileDiagnostic> get serializer => _$FileDiagnosticSerializer();
}

class _$FileDiagnosticSerializer implements PrimitiveSerializer<FileDiagnostic> {
  @override
  final Iterable<Type> types = const [FileDiagnostic, _$FileDiagnostic];

  @override
  final String wireName = r'FileDiagnostic';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FileDiagnostic object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'path';
    yield serializers.serialize(
      object.path,
      specifiedType: const FullType(String),
    );
    yield r'origin';
    yield serializers.serialize(
      object.origin,
      specifiedType: const FullType(String),
    );
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(String),
    );
    yield r'severity';
    yield serializers.serialize(
      object.severity,
      specifiedType: const FullType(String),
    );
    if (object.tagKey != null) {
      yield r'tagKey';
      yield serializers.serialize(
        object.tagKey,
        specifiedType: const FullType(String),
      );
    }
    if (object.detail != null) {
      yield r'detail';
      yield serializers.serialize(
        object.detail,
        specifiedType: const FullType(String),
      );
    }
    yield r'seenAt';
    yield serializers.serialize(
      object.seenAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    FileDiagnostic object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required FileDiagnosticBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.path = valueDes;
          break;
        case r'origin':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.origin = valueDes;
          break;
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
          break;
        case r'severity':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.severity = valueDes;
          break;
        case r'tagKey':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.tagKey = valueDes;
          break;
        case r'detail':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.detail = valueDes;
          break;
        case r'seenAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.seenAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  FileDiagnostic deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = FileDiagnosticBuilder();
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

