//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upload_target.g.dart';

/// One library an upload or acquisition may name. Deliberately narrower than the administrative library listing: a name, what it accepts, and whether it is managed. No path, no item count. 
///
/// Properties:
/// * [pid] - Library PID, as `libraryPid` takes it.
/// * [name] - Display name (the configured root name).
/// * [mediaTypes] - The media this library accepts, resolved for the caller: a mixed library lists every kind it takes, so a client filters on membership rather than having to know what `mixed` means. Podcast libraries are not upload targets and never appear. 
/// * [managed] - Whether the library is a managed root, and so a place the catalog can put files. Reported for a client that wants to say so; naming an unmanaged library is allowed, because the pid selects policy rather than placement. 
@BuiltValue()
abstract class UploadTarget implements Built<UploadTarget, UploadTargetBuilder> {
  /// Library PID, as `libraryPid` takes it.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Display name (the configured root name).
  @BuiltValueField(wireName: r'name')
  String get name;

  /// The media this library accepts, resolved for the caller: a mixed library lists every kind it takes, so a client filters on membership rather than having to know what `mixed` means. Podcast libraries are not upload targets and never appear. 
  @BuiltValueField(wireName: r'mediaTypes')
  BuiltList<MediaType> get mediaTypes;

  /// Whether the library is a managed root, and so a place the catalog can put files. Reported for a client that wants to say so; naming an unmanaged library is allowed, because the pid selects policy rather than placement. 
  @BuiltValueField(wireName: r'managed')
  bool get managed;

  UploadTarget._();

  factory UploadTarget([void updates(UploadTargetBuilder b)]) = _$UploadTarget;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UploadTargetBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UploadTarget> get serializer => _$UploadTargetSerializer();
}

class _$UploadTargetSerializer implements PrimitiveSerializer<UploadTarget> {
  @override
  final Iterable<Type> types = const [UploadTarget, _$UploadTarget];

  @override
  final String wireName = r'UploadTarget';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UploadTarget object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'mediaTypes';
    yield serializers.serialize(
      object.mediaTypes,
      specifiedType: const FullType(BuiltList, [FullType(MediaType)]),
    );
    yield r'managed';
    yield serializers.serialize(
      object.managed,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UploadTarget object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UploadTargetBuilder result,
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
        case r'mediaTypes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(MediaType)]),
          ) as BuiltList<MediaType>;
          result.mediaTypes.replace(valueDes);
          break;
        case r'managed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.managed = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UploadTarget deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UploadTargetBuilder();
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

