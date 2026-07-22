//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upload_quota.g.dart';

/// The caller's upload allowance: always their own, even for administrators listing everyone's sessions. Treat absence on a page as unknown, not unlimited. 
///
/// Properties:
/// * [bytesInUse] - Declared bytes of the caller's live sessions (everything not discarded); what quota checks charge. 
/// * [quotaBytes] - The account's cap on `bytesInUse`; absent means no per-user cap. 
@BuiltValue()
abstract class UploadQuota implements Built<UploadQuota, UploadQuotaBuilder> {
  /// Declared bytes of the caller's live sessions (everything not discarded); what quota checks charge. 
  @BuiltValueField(wireName: r'bytesInUse')
  int get bytesInUse;

  /// The account's cap on `bytesInUse`; absent means no per-user cap. 
  @BuiltValueField(wireName: r'quotaBytes')
  int? get quotaBytes;

  UploadQuota._();

  factory UploadQuota([void updates(UploadQuotaBuilder b)]) = _$UploadQuota;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UploadQuotaBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UploadQuota> get serializer => _$UploadQuotaSerializer();
}

class _$UploadQuotaSerializer implements PrimitiveSerializer<UploadQuota> {
  @override
  final Iterable<Type> types = const [UploadQuota, _$UploadQuota];

  @override
  final String wireName = r'UploadQuota';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UploadQuota object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'bytesInUse';
    yield serializers.serialize(
      object.bytesInUse,
      specifiedType: const FullType(int),
    );
    if (object.quotaBytes != null) {
      yield r'quotaBytes';
      yield serializers.serialize(
        object.quotaBytes,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    UploadQuota object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UploadQuotaBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'bytesInUse':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.bytesInUse = valueDes;
          break;
        case r'quotaBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.quotaBytes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UploadQuota deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UploadQuotaBuilder();
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

