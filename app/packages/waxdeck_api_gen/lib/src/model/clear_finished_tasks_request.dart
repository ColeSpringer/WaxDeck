//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'clear_finished_tasks_request.g.dart';

/// Which tasks a clear-finished sweep removes.
///
/// Properties:
/// * [scope] - `mine` clears the caller's own finished tasks. `all` clears every account's and is for administrators only. 
@BuiltValue()
abstract class ClearFinishedTasksRequest implements Built<ClearFinishedTasksRequest, ClearFinishedTasksRequestBuilder> {
  /// `mine` clears the caller's own finished tasks. `all` clears every account's and is for administrators only. 
  @BuiltValueField(wireName: r'scope')
  ClearFinishedTasksRequestScopeEnum? get scope;
  // enum scopeEnum {  mine,  all,  };

  ClearFinishedTasksRequest._();

  factory ClearFinishedTasksRequest([void updates(ClearFinishedTasksRequestBuilder b)]) = _$ClearFinishedTasksRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ClearFinishedTasksRequestBuilder b) => b
      ..scope = ClearFinishedTasksRequestScopeEnum.valueOf('mine');

  @BuiltValueSerializer(custom: true)
  static Serializer<ClearFinishedTasksRequest> get serializer => _$ClearFinishedTasksRequestSerializer();
}

class _$ClearFinishedTasksRequestSerializer implements PrimitiveSerializer<ClearFinishedTasksRequest> {
  @override
  final Iterable<Type> types = const [ClearFinishedTasksRequest, _$ClearFinishedTasksRequest];

  @override
  final String wireName = r'ClearFinishedTasksRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ClearFinishedTasksRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.scope != null) {
      yield r'scope';
      yield serializers.serialize(
        object.scope,
        specifiedType: const FullType(ClearFinishedTasksRequestScopeEnum),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ClearFinishedTasksRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ClearFinishedTasksRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'scope':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(ClearFinishedTasksRequestScopeEnum),
          ) as ClearFinishedTasksRequestScopeEnum?;
          if (valueDes == null) continue;
          result.scope = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ClearFinishedTasksRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ClearFinishedTasksRequestBuilder();
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


/// `mine` clears the caller's own finished tasks. `all` clears every account's and is for administrators only. 
class ClearFinishedTasksRequestScopeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'mine')
  static const ClearFinishedTasksRequestScopeEnum mine = _$clearFinishedTasksRequestScopeEnum_mine;
  @BuiltValueEnumConst(wireName: r'all')
  static const ClearFinishedTasksRequestScopeEnum all = _$clearFinishedTasksRequestScopeEnum_all;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const ClearFinishedTasksRequestScopeEnum unknownDefaultOpenApi = _$clearFinishedTasksRequestScopeEnum_unknownDefaultOpenApi;

  static Serializer<ClearFinishedTasksRequestScopeEnum> get serializer => _$clearFinishedTasksRequestScopeEnumSerializer;

  const ClearFinishedTasksRequestScopeEnum._(String name): super(name);

  static BuiltSet<ClearFinishedTasksRequestScopeEnum> get values => _$clearFinishedTasksRequestScopeEnumValues;
  static ClearFinishedTasksRequestScopeEnum valueOf(String name) => _$clearFinishedTasksRequestScopeEnumValueOf(name);
}

