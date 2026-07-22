//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/upload.dart';
import 'package:waxdeck_api_gen/src/model/upload_quota.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upload_page.g.dart';

/// One page of uploads.
///
/// Properties:
/// * [uploads] - Uploads, newest first.
/// * [nextCursor] - Cursor for the next page; omitted on the last.
/// * [quota] 
@BuiltValue()
abstract class UploadPage implements Built<UploadPage, UploadPageBuilder> {
  /// Uploads, newest first.
  @BuiltValueField(wireName: r'uploads')
  BuiltList<Upload> get uploads;

  /// Cursor for the next page; omitted on the last.
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  @BuiltValueField(wireName: r'quota')
  UploadQuota? get quota;

  UploadPage._();

  factory UploadPage([void updates(UploadPageBuilder b)]) = _$UploadPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UploadPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UploadPage> get serializer => _$UploadPageSerializer();
}

class _$UploadPageSerializer implements PrimitiveSerializer<UploadPage> {
  @override
  final Iterable<Type> types = const [UploadPage, _$UploadPage];

  @override
  final String wireName = r'UploadPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UploadPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'uploads';
    yield serializers.serialize(
      object.uploads,
      specifiedType: const FullType(BuiltList, [FullType(Upload)]),
    );
    if (object.nextCursor != null) {
      yield r'nextCursor';
      yield serializers.serialize(
        object.nextCursor,
        specifiedType: const FullType(String),
      );
    }
    if (object.quota != null) {
      yield r'quota';
      yield serializers.serialize(
        object.quota,
        specifiedType: const FullType(UploadQuota),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    UploadPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UploadPageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'uploads':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Upload)]),
          ) as BuiltList<Upload>;
          result.uploads.replace(valueDes);
          break;
        case r'nextCursor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nextCursor = valueDes;
          break;
        case r'quota':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(UploadQuota),
          ) as UploadQuota;
          result.quota.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UploadPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UploadPageBuilder();
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

