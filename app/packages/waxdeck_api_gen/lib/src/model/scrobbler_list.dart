//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/scrobbler.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'scrobbler_list.g.dart';

/// The caller's scrobbling connection slots.
///
/// Properties:
/// * [scrobblers] - One entry per known service.
@BuiltValue()
abstract class ScrobblerList implements Built<ScrobblerList, ScrobblerListBuilder> {
  /// One entry per known service.
  @BuiltValueField(wireName: r'scrobblers')
  BuiltList<Scrobbler> get scrobblers;

  ScrobblerList._();

  factory ScrobblerList([void updates(ScrobblerListBuilder b)]) = _$ScrobblerList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ScrobblerListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ScrobblerList> get serializer => _$ScrobblerListSerializer();
}

class _$ScrobblerListSerializer implements PrimitiveSerializer<ScrobblerList> {
  @override
  final Iterable<Type> types = const [ScrobblerList, _$ScrobblerList];

  @override
  final String wireName = r'ScrobblerList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ScrobblerList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'scrobblers';
    yield serializers.serialize(
      object.scrobblers,
      specifiedType: const FullType(BuiltList, [FullType(Scrobbler)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ScrobblerList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ScrobblerListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'scrobblers':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Scrobbler)]),
          ) as BuiltList<Scrobbler>;
          result.scrobblers.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ScrobblerList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ScrobblerListBuilder();
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

