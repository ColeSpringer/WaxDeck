//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'health.g.dart';

/// Liveness and version information.
///
/// Properties:
/// * [status] - Always `ok` when the server can respond.
/// * [version] - Server build version.
/// * [apiVersion] - Major API version served under `/api/v1`.
/// * [uploadFormats] - File extensions uploads accept (lowercase, no dot) - the effective set, so an operator's `WAXDECK_UPLOAD_FORMATS` replacement is what appears here, with `rejectedFormats` subtracted (the deny-list wins at the gate whatever the operator listed). Clients filter pickers and drop zones against it; the format check at upload-session create remains the authoritative gate. Absent on servers older than the field. 
/// * [rejectedFormats] - File extensions refused outright whatever `uploadFormats` says (DRM containers, encrypted by construction). Clients use it to tell \"can never play\" apart from \"not in the accepted set\" when reporting what a filter dropped. Absent on servers older than the field. 
@BuiltValue()
abstract class Health implements Built<Health, HealthBuilder> {
  /// Always `ok` when the server can respond.
  @BuiltValueField(wireName: r'status')
  String get status;

  /// Server build version.
  @BuiltValueField(wireName: r'version')
  String get version;

  /// Major API version served under `/api/v1`.
  @BuiltValueField(wireName: r'apiVersion')
  int get apiVersion;

  /// File extensions uploads accept (lowercase, no dot) - the effective set, so an operator's `WAXDECK_UPLOAD_FORMATS` replacement is what appears here, with `rejectedFormats` subtracted (the deny-list wins at the gate whatever the operator listed). Clients filter pickers and drop zones against it; the format check at upload-session create remains the authoritative gate. Absent on servers older than the field. 
  @BuiltValueField(wireName: r'uploadFormats')
  BuiltList<String>? get uploadFormats;

  /// File extensions refused outright whatever `uploadFormats` says (DRM containers, encrypted by construction). Clients use it to tell \"can never play\" apart from \"not in the accepted set\" when reporting what a filter dropped. Absent on servers older than the field. 
  @BuiltValueField(wireName: r'rejectedFormats')
  BuiltList<String>? get rejectedFormats;

  Health._();

  factory Health([void updates(HealthBuilder b)]) = _$Health;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HealthBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Health> get serializer => _$HealthSerializer();
}

class _$HealthSerializer implements PrimitiveSerializer<Health> {
  @override
  final Iterable<Type> types = const [Health, _$Health];

  @override
  final String wireName = r'Health';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Health object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(String),
    );
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(String),
    );
    yield r'apiVersion';
    yield serializers.serialize(
      object.apiVersion,
      specifiedType: const FullType(int),
    );
    if (object.uploadFormats != null) {
      yield r'uploadFormats';
      yield serializers.serialize(
        object.uploadFormats,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.rejectedFormats != null) {
      yield r'rejectedFormats';
      yield serializers.serialize(
        object.rejectedFormats,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Health object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required HealthBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.status = valueDes;
          break;
        case r'version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.version = valueDes;
          break;
        case r'apiVersion':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.apiVersion = valueDes;
          break;
        case r'uploadFormats':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.uploadFormats.replace(valueDes);
          break;
        case r'rejectedFormats':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.rejectedFormats.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Health deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HealthBuilder();
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

