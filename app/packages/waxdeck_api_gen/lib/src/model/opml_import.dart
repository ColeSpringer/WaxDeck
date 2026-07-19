//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'opml_import.g.dart';

/// An OPML document to import.
///
/// Properties:
/// * [opml] - The OPML XML document, verbatim.
@BuiltValue()
abstract class OpmlImport implements Built<OpmlImport, OpmlImportBuilder> {
  /// The OPML XML document, verbatim.
  @BuiltValueField(wireName: r'opml')
  String get opml;

  OpmlImport._();

  factory OpmlImport([void updates(OpmlImportBuilder b)]) = _$OpmlImport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OpmlImportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OpmlImport> get serializer => _$OpmlImportSerializer();
}

class _$OpmlImportSerializer implements PrimitiveSerializer<OpmlImport> {
  @override
  final Iterable<Type> types = const [OpmlImport, _$OpmlImport];

  @override
  final String wireName = r'OpmlImport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OpmlImport object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'opml';
    yield serializers.serialize(
      object.opml,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    OpmlImport object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OpmlImportBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'opml':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.opml = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OpmlImport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OpmlImportBuilder();
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

