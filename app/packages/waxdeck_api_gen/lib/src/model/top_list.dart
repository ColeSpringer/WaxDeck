//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/top_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'top_list.g.dart';

/// One ranked top list.
///
/// Properties:
/// * [kind] - Which top list this is.
/// * [range] - The range that was aggregated.
/// * [entries] - Ranked entries, most listening time first.
@BuiltValue()
abstract class TopList implements Built<TopList, TopListBuilder> {
  /// Which top list this is.
  @BuiltValueField(wireName: r'kind')
  TopListKindEnum get kind;
  // enum kindEnum {  artists,  albums,  genres,  shows,  stations,  };

  /// The range that was aggregated.
  @BuiltValueField(wireName: r'range')
  TopListRangeEnum get range;
  // enum rangeEnum {  7d,  30d,  90d,  365d,  all,  };

  /// Ranked entries, most listening time first.
  @BuiltValueField(wireName: r'entries')
  BuiltList<TopEntry> get entries;

  TopList._();

  factory TopList([void updates(TopListBuilder b)]) = _$TopList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TopListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TopList> get serializer => _$TopListSerializer();
}

class _$TopListSerializer implements PrimitiveSerializer<TopList> {
  @override
  final Iterable<Type> types = const [TopList, _$TopList];

  @override
  final String wireName = r'TopList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TopList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(TopListKindEnum),
    );
    yield r'range';
    yield serializers.serialize(
      object.range,
      specifiedType: const FullType(TopListRangeEnum),
    );
    yield r'entries';
    yield serializers.serialize(
      object.entries,
      specifiedType: const FullType(BuiltList, [FullType(TopEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    TopList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TopListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(TopListKindEnum),
          ) as TopListKindEnum;
          result.kind = valueDes;
          break;
        case r'range':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(TopListRangeEnum),
          ) as TopListRangeEnum;
          result.range = valueDes;
          break;
        case r'entries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(TopEntry)]),
          ) as BuiltList<TopEntry>;
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
  TopList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TopListBuilder();
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

class TopListKindEnum extends EnumClass {

  /// Which top list this is.
  @BuiltValueEnumConst(wireName: r'artists')
  static const TopListKindEnum artists = _$topListKindEnum_artists;
  /// Which top list this is.
  @BuiltValueEnumConst(wireName: r'albums')
  static const TopListKindEnum albums = _$topListKindEnum_albums;
  /// Which top list this is.
  @BuiltValueEnumConst(wireName: r'genres')
  static const TopListKindEnum genres = _$topListKindEnum_genres;
  /// Which top list this is.
  @BuiltValueEnumConst(wireName: r'shows')
  static const TopListKindEnum shows = _$topListKindEnum_shows;
  /// Which top list this is.
  @BuiltValueEnumConst(wireName: r'stations')
  static const TopListKindEnum stations = _$topListKindEnum_stations;
  /// Which top list this is.
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const TopListKindEnum unknownDefaultOpenApi = _$topListKindEnum_unknownDefaultOpenApi;

  static Serializer<TopListKindEnum> get serializer => _$topListKindEnumSerializer;

  const TopListKindEnum._(String name): super(name);

  static BuiltSet<TopListKindEnum> get values => _$topListKindEnumValues;
  static TopListKindEnum valueOf(String name) => _$topListKindEnumValueOf(name);
}

class TopListRangeEnum extends EnumClass {

  /// The range that was aggregated.
  @BuiltValueEnumConst(wireName: r'7d')
  static const TopListRangeEnum n7d = _$topListRangeEnum_n7d;
  /// The range that was aggregated.
  @BuiltValueEnumConst(wireName: r'30d')
  static const TopListRangeEnum n30d = _$topListRangeEnum_n30d;
  /// The range that was aggregated.
  @BuiltValueEnumConst(wireName: r'90d')
  static const TopListRangeEnum n90d = _$topListRangeEnum_n90d;
  /// The range that was aggregated.
  @BuiltValueEnumConst(wireName: r'365d')
  static const TopListRangeEnum n365d = _$topListRangeEnum_n365d;
  /// The range that was aggregated.
  @BuiltValueEnumConst(wireName: r'all')
  static const TopListRangeEnum all = _$topListRangeEnum_all;
  /// The range that was aggregated.
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const TopListRangeEnum unknownDefaultOpenApi = _$topListRangeEnum_unknownDefaultOpenApi;

  static Serializer<TopListRangeEnum> get serializer => _$topListRangeEnumSerializer;

  const TopListRangeEnum._(String name): super(name);

  static BuiltSet<TopListRangeEnum> get values => _$topListRangeEnumValues;
  static TopListRangeEnum valueOf(String name) => _$topListRangeEnumValueOf(name);
}

