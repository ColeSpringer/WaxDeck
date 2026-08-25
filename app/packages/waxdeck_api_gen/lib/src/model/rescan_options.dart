//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rescan_options.g.dart';

/// What kind of scan to run.
///
/// Properties:
/// * [force] - Re-read every file even when its size and mtime are unchanged, re-hashing and re-parsing tags - the repair pass for rows written before a parser fix, priced at a full library read. Curated fields stay preserved: a forced scan never overrides locked edits. 
@BuiltValue()
abstract class RescanOptions implements Built<RescanOptions, RescanOptionsBuilder> {
  /// Re-read every file even when its size and mtime are unchanged, re-hashing and re-parsing tags - the repair pass for rows written before a parser fix, priced at a full library read. Curated fields stay preserved: a forced scan never overrides locked edits. 
  @BuiltValueField(wireName: r'force')
  bool? get force;

  RescanOptions._();

  factory RescanOptions([void updates(RescanOptionsBuilder b)]) = _$RescanOptions;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RescanOptionsBuilder b) => b
      ..force = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<RescanOptions> get serializer => _$RescanOptionsSerializer();
}

class _$RescanOptionsSerializer implements PrimitiveSerializer<RescanOptions> {
  @override
  final Iterable<Type> types = const [RescanOptions, _$RescanOptions];

  @override
  final String wireName = r'RescanOptions';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RescanOptions object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.force != null) {
      yield r'force';
      yield serializers.serialize(
        object.force,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RescanOptions object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RescanOptionsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'force':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.force = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RescanOptions deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RescanOptionsBuilder();
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

