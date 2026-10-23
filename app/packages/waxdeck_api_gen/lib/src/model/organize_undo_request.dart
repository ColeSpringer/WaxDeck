//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'organize_undo_request.g.dart';

/// The run to undo.
///
/// Properties:
/// * [jobPid] - The organize run's job, as the history lists it.
@BuiltValue()
abstract class OrganizeUndoRequest implements Built<OrganizeUndoRequest, OrganizeUndoRequestBuilder> {
  /// The organize run's job, as the history lists it.
  @BuiltValueField(wireName: r'jobPid')
  String get jobPid;

  OrganizeUndoRequest._();

  factory OrganizeUndoRequest([void updates(OrganizeUndoRequestBuilder b)]) = _$OrganizeUndoRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OrganizeUndoRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OrganizeUndoRequest> get serializer => _$OrganizeUndoRequestSerializer();
}

class _$OrganizeUndoRequestSerializer implements PrimitiveSerializer<OrganizeUndoRequest> {
  @override
  final Iterable<Type> types = const [OrganizeUndoRequest, _$OrganizeUndoRequest];

  @override
  final String wireName = r'OrganizeUndoRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OrganizeUndoRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'jobPid';
    yield serializers.serialize(
      object.jobPid,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    OrganizeUndoRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OrganizeUndoRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'jobPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.jobPid = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OrganizeUndoRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OrganizeUndoRequestBuilder();
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


