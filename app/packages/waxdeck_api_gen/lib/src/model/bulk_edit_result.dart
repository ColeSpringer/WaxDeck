//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/write_back_failure.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bulk_edit_result.g.dart';

/// Per-item outcomes of a bulk edit.
///
/// Properties:
/// * [edited] - Items whose catalog rows updated.
/// * [skipped] - Items skipped for locks.
/// * [writeBackFailures] - Files whose tags could not be updated.
@BuiltValue()
abstract class BulkEditResult implements Built<BulkEditResult, BulkEditResultBuilder> {
  /// Items whose catalog rows updated.
  @BuiltValueField(wireName: r'edited')
  BuiltList<String> get edited;

  /// Items skipped for locks.
  @BuiltValueField(wireName: r'skipped')
  BuiltList<String> get skipped;

  /// Files whose tags could not be updated.
  @BuiltValueField(wireName: r'writeBackFailures')
  BuiltList<WriteBackFailure>? get writeBackFailures;

  BulkEditResult._();

  factory BulkEditResult([void updates(BulkEditResultBuilder b)]) = _$BulkEditResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BulkEditResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BulkEditResult> get serializer => _$BulkEditResultSerializer();
}

class _$BulkEditResultSerializer implements PrimitiveSerializer<BulkEditResult> {
  @override
  final Iterable<Type> types = const [BulkEditResult, _$BulkEditResult];

  @override
  final String wireName = r'BulkEditResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BulkEditResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'edited';
    yield serializers.serialize(
      object.edited,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'skipped';
    yield serializers.serialize(
      object.skipped,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    if (object.writeBackFailures != null) {
      yield r'writeBackFailures';
      yield serializers.serialize(
        object.writeBackFailures,
        specifiedType: const FullType(BuiltList, [FullType(WriteBackFailure)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BulkEditResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BulkEditResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'edited':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.edited.replace(valueDes);
          break;
        case r'skipped':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.skipped.replace(valueDes);
          break;
        case r'writeBackFailures':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(WriteBackFailure)]),
          ) as BuiltList<WriteBackFailure>;
          result.writeBackFailures.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BulkEditResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BulkEditResultBuilder();
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

