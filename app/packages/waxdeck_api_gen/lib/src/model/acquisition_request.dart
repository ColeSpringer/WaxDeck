//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/acquisition_format.dart';
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'acquisition_request.g.dart';

/// One source URL to acquire.
///
/// Properties:
/// * [url] - The source URL: a single video, a playlist, or a channel the acquisition bridge understands. 
/// * [mediaType] 
/// * [libraryPid] - Target library; required when several libraries of the media type are visible to the caller. 
/// * [format] 
@BuiltValue()
abstract class AcquisitionRequest implements Built<AcquisitionRequest, AcquisitionRequestBuilder> {
  /// The source URL: a single video, a playlist, or a channel the acquisition bridge understands. 
  @BuiltValueField(wireName: r'url')
  String get url;

  @BuiltValueField(wireName: r'mediaType')
  MediaType get mediaType;
  // enum mediaTypeEnum {  music,  podcast,  audiobook,  };

  /// Target library; required when several libraries of the media type are visible to the caller. 
  @BuiltValueField(wireName: r'libraryPid')
  String? get libraryPid;

  @BuiltValueField(wireName: r'format')
  AcquisitionFormat? get format;
  // enum formatEnum {  best,  opus,  mp3,  m4a,  flac,  };

  AcquisitionRequest._();

  factory AcquisitionRequest([void updates(AcquisitionRequestBuilder b)]) = _$AcquisitionRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AcquisitionRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AcquisitionRequest> get serializer => _$AcquisitionRequestSerializer();
}

class _$AcquisitionRequestSerializer implements PrimitiveSerializer<AcquisitionRequest> {
  @override
  final Iterable<Type> types = const [AcquisitionRequest, _$AcquisitionRequest];

  @override
  final String wireName = r'AcquisitionRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AcquisitionRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'url';
    yield serializers.serialize(
      object.url,
      specifiedType: const FullType(String),
    );
    yield r'mediaType';
    yield serializers.serialize(
      object.mediaType,
      specifiedType: const FullType(MediaType),
    );
    if (object.libraryPid != null) {
      yield r'libraryPid';
      yield serializers.serialize(
        object.libraryPid,
        specifiedType: const FullType(String),
      );
    }
    if (object.format != null) {
      yield r'format';
      yield serializers.serialize(
        object.format,
        specifiedType: const FullType(AcquisitionFormat),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AcquisitionRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AcquisitionRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.url = valueDes;
          break;
        case r'mediaType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MediaType),
          ) as MediaType;
          result.mediaType = valueDes;
          break;
        case r'libraryPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.libraryPid = valueDes;
          break;
        case r'format':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AcquisitionFormat),
          ) as AcquisitionFormat;
          result.format = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AcquisitionRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AcquisitionRequestBuilder();
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

