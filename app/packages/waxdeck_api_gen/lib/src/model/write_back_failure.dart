//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'write_back_failure.g.dart';

/// One file a write-back could not update.
///
/// Properties:
/// * [filePid] - The file.
/// * [path] - Its display path.
/// * [reason] - Why the write failed or was refused.
@BuiltValue()
abstract class WriteBackFailure implements Built<WriteBackFailure, WriteBackFailureBuilder> {
  /// The file.
  @BuiltValueField(wireName: r'filePid')
  String get filePid;

  /// Its display path.
  @BuiltValueField(wireName: r'path')
  String? get path;

  /// Why the write failed or was refused.
  @BuiltValueField(wireName: r'reason')
  String get reason;

  WriteBackFailure._();

  factory WriteBackFailure([void updates(WriteBackFailureBuilder b)]) = _$WriteBackFailure;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WriteBackFailureBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WriteBackFailure> get serializer => _$WriteBackFailureSerializer();
}

class _$WriteBackFailureSerializer implements PrimitiveSerializer<WriteBackFailure> {
  @override
  final Iterable<Type> types = const [WriteBackFailure, _$WriteBackFailure];

  @override
  final String wireName = r'WriteBackFailure';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WriteBackFailure object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'filePid';
    yield serializers.serialize(
      object.filePid,
      specifiedType: const FullType(String),
    );
    if (object.path != null) {
      yield r'path';
      yield serializers.serialize(
        object.path,
        specifiedType: const FullType(String),
      );
    }
    yield r'reason';
    yield serializers.serialize(
      object.reason,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    WriteBackFailure object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WriteBackFailureBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'filePid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.filePid = valueDes;
          break;
        case r'path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.path = valueDes;
          break;
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reason = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WriteBackFailure deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WriteBackFailureBuilder();
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

