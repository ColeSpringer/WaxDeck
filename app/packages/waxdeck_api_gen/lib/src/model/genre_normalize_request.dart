//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'genre_normalize_request.g.dart';

/// A full-catalog genre normalization to start.
///
/// Properties:
/// * [dryRun] - Report what would be rewritten without writing.
@BuiltValue()
abstract class GenreNormalizeRequest implements Built<GenreNormalizeRequest, GenreNormalizeRequestBuilder> {
  /// Report what would be rewritten without writing.
  @BuiltValueField(wireName: r'dryRun')
  bool? get dryRun;

  GenreNormalizeRequest._();

  factory GenreNormalizeRequest([void updates(GenreNormalizeRequestBuilder b)]) = _$GenreNormalizeRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GenreNormalizeRequestBuilder b) => b
      ..dryRun = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<GenreNormalizeRequest> get serializer => _$GenreNormalizeRequestSerializer();
}

class _$GenreNormalizeRequestSerializer implements PrimitiveSerializer<GenreNormalizeRequest> {
  @override
  final Iterable<Type> types = const [GenreNormalizeRequest, _$GenreNormalizeRequest];

  @override
  final String wireName = r'GenreNormalizeRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GenreNormalizeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.dryRun != null) {
      yield r'dryRun';
      yield serializers.serialize(
        object.dryRun,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    GenreNormalizeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GenreNormalizeRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'dryRun':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.dryRun = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GenreNormalizeRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GenreNormalizeRequestBuilder();
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

