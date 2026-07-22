//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/trash_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'trash_list.g.dart';

/// The trash journal.
///
/// Properties:
/// * [entries] - Entries, newest first.
@BuiltValue()
abstract class TrashList implements Built<TrashList, TrashListBuilder> {
  /// Entries, newest first.
  @BuiltValueField(wireName: r'entries')
  BuiltList<TrashEntry> get entries;

  TrashList._();

  factory TrashList([void updates(TrashListBuilder b)]) = _$TrashList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TrashListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TrashList> get serializer => _$TrashListSerializer();
}

class _$TrashListSerializer implements PrimitiveSerializer<TrashList> {
  @override
  final Iterable<Type> types = const [TrashList, _$TrashList];

  @override
  final String wireName = r'TrashList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TrashList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entries';
    yield serializers.serialize(
      object.entries,
      specifiedType: const FullType(BuiltList, [FullType(TrashEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    TrashList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TrashListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(TrashEntry)]),
          ) as BuiltList<TrashEntry>;
          result.entries.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TrashList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TrashListBuilder();
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

