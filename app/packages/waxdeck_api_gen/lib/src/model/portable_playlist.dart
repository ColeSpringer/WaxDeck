//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/portable_ref.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'portable_playlist.g.dart';

/// A playlist exported as portable refs, in playlist order.
///
/// Properties:
/// * [name] - The playlist's name.
/// * [refs] 
@BuiltValue()
abstract class PortablePlaylist implements Built<PortablePlaylist, PortablePlaylistBuilder> {
  /// The playlist's name.
  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'refs')
  BuiltList<PortableRef> get refs;

  PortablePlaylist._();

  factory PortablePlaylist([void updates(PortablePlaylistBuilder b)]) = _$PortablePlaylist;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PortablePlaylistBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PortablePlaylist> get serializer => _$PortablePlaylistSerializer();
}

class _$PortablePlaylistSerializer implements PrimitiveSerializer<PortablePlaylist> {
  @override
  final Iterable<Type> types = const [PortablePlaylist, _$PortablePlaylist];

  @override
  final String wireName = r'PortablePlaylist';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PortablePlaylist object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'refs';
    yield serializers.serialize(
      object.refs,
      specifiedType: const FullType(BuiltList, [FullType(PortableRef)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PortablePlaylist object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PortablePlaylistBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'refs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PortableRef)]),
          ) as BuiltList<PortableRef>;
          result.refs.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PortablePlaylist deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PortablePlaylistBuilder();
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

