//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bulk_edit.g.dart';

/// The same scalar edits applied to many items.
///
/// Properties:
/// * [itemPids] - The items to edit.
/// * [fields] - Field name to new value, applied to every item.
/// * [writeBack] - Also write into the files' tags.
/// * [skipLocked] - Skip items whose target fields are locked instead of failing the batch. 
/// * [force] - Override locks (mutually exclusive with `skipLocked`).
@BuiltValue()
abstract class BulkEdit implements Built<BulkEdit, BulkEditBuilder> {
  /// The items to edit.
  @BuiltValueField(wireName: r'itemPids')
  BuiltList<String> get itemPids;

  /// Field name to new value, applied to every item.
  @BuiltValueField(wireName: r'fields')
  BuiltMap<String, String> get fields;

  /// Also write into the files' tags.
  @BuiltValueField(wireName: r'writeBack')
  bool? get writeBack;

  /// Skip items whose target fields are locked instead of failing the batch. 
  @BuiltValueField(wireName: r'skipLocked')
  bool? get skipLocked;

  /// Override locks (mutually exclusive with `skipLocked`).
  @BuiltValueField(wireName: r'force')
  bool? get force;

  BulkEdit._();

  factory BulkEdit([void updates(BulkEditBuilder b)]) = _$BulkEdit;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BulkEditBuilder b) => b
      ..writeBack = false
      ..skipLocked = false
      ..force = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<BulkEdit> get serializer => _$BulkEditSerializer();
}

class _$BulkEditSerializer implements PrimitiveSerializer<BulkEdit> {
  @override
  final Iterable<Type> types = const [BulkEdit, _$BulkEdit];

  @override
  final String wireName = r'BulkEdit';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BulkEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'itemPids';
    yield serializers.serialize(
      object.itemPids,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'fields';
    yield serializers.serialize(
      object.fields,
      specifiedType: const FullType(BuiltMap, [FullType(String), FullType(String)]),
    );
    if (object.writeBack != null) {
      yield r'writeBack';
      yield serializers.serialize(
        object.writeBack,
        specifiedType: const FullType(bool),
      );
    }
    if (object.skipLocked != null) {
      yield r'skipLocked';
      yield serializers.serialize(
        object.skipLocked,
        specifiedType: const FullType(bool),
      );
    }
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
    BulkEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BulkEditBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'itemPids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.itemPids.replace(valueDes);
          break;
        case r'fields':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType(String)]),
          ) as BuiltMap<String, String>;
          result.fields.replace(valueDes);
          break;
        case r'writeBack':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.writeBack = valueDes;
          break;
        case r'skipLocked':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.skipLocked = valueDes;
          break;
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
  BulkEdit deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BulkEditBuilder();
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

