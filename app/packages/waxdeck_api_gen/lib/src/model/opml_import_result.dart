//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/opml_import_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'opml_import_result.g.dart';

/// Per-feed outcomes of an OPML import.
///
/// Properties:
/// * [results] 
@BuiltValue()
abstract class OpmlImportResult implements Built<OpmlImportResult, OpmlImportResultBuilder> {
  @BuiltValueField(wireName: r'results')
  BuiltList<OpmlImportEntry> get results;

  OpmlImportResult._();

  factory OpmlImportResult([void updates(OpmlImportResultBuilder b)]) = _$OpmlImportResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OpmlImportResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OpmlImportResult> get serializer => _$OpmlImportResultSerializer();
}

class _$OpmlImportResultSerializer implements PrimitiveSerializer<OpmlImportResult> {
  @override
  final Iterable<Type> types = const [OpmlImportResult, _$OpmlImportResult];

  @override
  final String wireName = r'OpmlImportResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OpmlImportResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'results';
    yield serializers.serialize(
      object.results,
      specifiedType: const FullType(BuiltList, [FullType(OpmlImportEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    OpmlImportResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OpmlImportResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'results':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(OpmlImportEntry)]),
          ) as BuiltList<OpmlImportEntry>;
          result.results.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OpmlImportResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OpmlImportResultBuilder();
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

