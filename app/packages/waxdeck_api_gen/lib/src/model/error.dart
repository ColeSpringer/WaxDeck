//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'error.g.dart';

/// Structured error. `code` is a stable machine-readable string (see the API-level description for defined codes); `message` is human-readable and not stable. 
///
/// Properties:
/// * [code] - Stable machine-readable error code.
/// * [message] - Human-readable explanation (not stable, do not parse).
/// * [params] - Machine-readable detail, where one code covers several causes a client has to tell apart. `code` names which keys can appear (see the API-level description); values are always strings. Best-effort per refusal, never guaranteed by code: an error of the same code with no params is an ordinary one, so read this as a refinement rather than requiring it. `message` says the same thing in prose, so a client that ignores this reads what it always read. Clients must ignore keys they do not know. 
@BuiltValue()
abstract class Error implements Built<Error, ErrorBuilder> {
  /// Stable machine-readable error code.
  @BuiltValueField(wireName: r'code')
  String get code;

  /// Human-readable explanation (not stable, do not parse).
  @BuiltValueField(wireName: r'message')
  String get message;

  /// Machine-readable detail, where one code covers several causes a client has to tell apart. `code` names which keys can appear (see the API-level description); values are always strings. Best-effort per refusal, never guaranteed by code: an error of the same code with no params is an ordinary one, so read this as a refinement rather than requiring it. `message` says the same thing in prose, so a client that ignores this reads what it always read. Clients must ignore keys they do not know. 
  @BuiltValueField(wireName: r'params')
  BuiltMap<String, String>? get params;

  Error._();

  factory Error([void updates(ErrorBuilder b)]) = _$Error;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ErrorBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Error> get serializer => _$ErrorSerializer();
}

class _$ErrorSerializer implements PrimitiveSerializer<Error> {
  @override
  final Iterable<Type> types = const [Error, _$Error];

  @override
  final String wireName = r'Error';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Error object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(String),
    );
    yield r'message';
    yield serializers.serialize(
      object.message,
      specifiedType: const FullType(String),
    );
    if (object.params != null) {
      yield r'params';
      yield serializers.serialize(
        object.params,
        specifiedType: const FullType(BuiltMap, [FullType(String), FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Error object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ErrorBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
          break;
        case r'message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.message = valueDes;
          break;
        case r'params':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType(String)]),
          ) as BuiltMap<String, String>;
          result.params.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Error deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ErrorBuilder();
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

