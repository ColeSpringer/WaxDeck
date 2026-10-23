//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/organize_batch.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'organize_history.g.dart';

/// A page of the organize runs the journal still holds.
///
/// Properties:
/// * [batches] - The runs, newest first.
/// * [nextCursor] - Cursor for the next, older page; absent on the last.
@BuiltValue()
abstract class OrganizeHistory implements Built<OrganizeHistory, OrganizeHistoryBuilder> {
  /// The runs, newest first.
  @BuiltValueField(wireName: r'batches')
  BuiltList<OrganizeBatch> get batches;

  /// Cursor for the next, older page; absent on the last.
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  OrganizeHistory._();

  factory OrganizeHistory([void updates(OrganizeHistoryBuilder b)]) = _$OrganizeHistory;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OrganizeHistoryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OrganizeHistory> get serializer => _$OrganizeHistorySerializer();
}

class _$OrganizeHistorySerializer implements PrimitiveSerializer<OrganizeHistory> {
  @override
  final Iterable<Type> types = const [OrganizeHistory, _$OrganizeHistory];

  @override
  final String wireName = r'OrganizeHistory';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OrganizeHistory object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'batches';
    yield serializers.serialize(
      object.batches,
      specifiedType: const FullType(BuiltList, [FullType(OrganizeBatch)]),
    );
    if (object.nextCursor != null) {
      yield r'nextCursor';
      yield serializers.serialize(
        object.nextCursor,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    OrganizeHistory object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OrganizeHistoryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'batches':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(OrganizeBatch)]),
          ) as BuiltList<OrganizeBatch>;
          result.batches.replace(valueDes);
          break;
        case r'nextCursor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.nextCursor = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OrganizeHistory deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OrganizeHistoryBuilder();
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


