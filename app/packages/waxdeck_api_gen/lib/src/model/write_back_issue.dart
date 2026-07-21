//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'write_back_issue.g.dart';

/// One file out of step with the catalog.
///
/// Properties:
/// * [filePid] - The backing file.
/// * [code] - The diagnostic: `tag-write-unsynced` (a write-back was refused or failed; the file's tags lag the catalog) or `tag-write-lost` (the write ran but the format could not store the value). A string, not a closed enum. 
/// * [tagKey] - The affected tag key, when known.
/// * [detail] - Human-readable detail.
@BuiltValue()
abstract class WriteBackIssue implements Built<WriteBackIssue, WriteBackIssueBuilder> {
  /// The backing file.
  @BuiltValueField(wireName: r'filePid')
  String get filePid;

  /// The diagnostic: `tag-write-unsynced` (a write-back was refused or failed; the file's tags lag the catalog) or `tag-write-lost` (the write ran but the format could not store the value). A string, not a closed enum. 
  @BuiltValueField(wireName: r'code')
  String get code;

  /// The affected tag key, when known.
  @BuiltValueField(wireName: r'tagKey')
  String? get tagKey;

  /// Human-readable detail.
  @BuiltValueField(wireName: r'detail')
  String? get detail;

  WriteBackIssue._();

  factory WriteBackIssue([void updates(WriteBackIssueBuilder b)]) = _$WriteBackIssue;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WriteBackIssueBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WriteBackIssue> get serializer => _$WriteBackIssueSerializer();
}

class _$WriteBackIssueSerializer implements PrimitiveSerializer<WriteBackIssue> {
  @override
  final Iterable<Type> types = const [WriteBackIssue, _$WriteBackIssue];

  @override
  final String wireName = r'WriteBackIssue';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WriteBackIssue object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'filePid';
    yield serializers.serialize(
      object.filePid,
      specifiedType: const FullType(String),
    );
    yield r'code';
    yield serializers.serialize(
      object.code,
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
  }

  @override
  Object serialize(
    Serializers serializers,
    WriteBackIssue object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WriteBackIssueBuilder result,
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
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WriteBackIssue deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WriteBackIssueBuilder();
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

