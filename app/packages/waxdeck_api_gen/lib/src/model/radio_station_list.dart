//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/radio_station.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'radio_station_list.g.dart';

/// The whole station library.
///
/// Properties:
/// * [stations] - Stations ordered by name.
@BuiltValue()
abstract class RadioStationList implements Built<RadioStationList, RadioStationListBuilder> {
  /// Stations ordered by name.
  @BuiltValueField(wireName: r'stations')
  BuiltList<RadioStation> get stations;

  RadioStationList._();

  factory RadioStationList([void updates(RadioStationListBuilder b)]) = _$RadioStationList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RadioStationListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RadioStationList> get serializer => _$RadioStationListSerializer();
}

class _$RadioStationListSerializer implements PrimitiveSerializer<RadioStationList> {
  @override
  final Iterable<Type> types = const [RadioStationList, _$RadioStationList];

  @override
  final String wireName = r'RadioStationList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RadioStationList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'stations';
    yield serializers.serialize(
      object.stations,
      specifiedType: const FullType(BuiltList, [FullType(RadioStation)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RadioStationList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RadioStationListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'stations':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RadioStation)]),
          ) as BuiltList<RadioStation>;
          result.stations.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RadioStationList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RadioStationListBuilder();
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

