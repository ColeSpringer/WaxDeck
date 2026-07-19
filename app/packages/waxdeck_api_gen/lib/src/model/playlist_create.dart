//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/smart_rule.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playlist_create.g.dart';

/// Create a playlist.
///
/// Properties:
/// * [name] - Display name.
/// * [kind] - `static` or `smart`.
/// * [visibility] - `private` (default) or `shared`.
/// * [rule] 
/// * [itemPids] - Initial members for a static playlist, in order. Invalid with `smart`. 
@BuiltValue()
abstract class PlaylistCreate implements Built<PlaylistCreate, PlaylistCreateBuilder> {
  /// Display name.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// `static` or `smart`.
  @BuiltValueField(wireName: r'kind')
  String get kind;

  /// `private` (default) or `shared`.
  @BuiltValueField(wireName: r'visibility')
  String? get visibility;

  @BuiltValueField(wireName: r'rule')
  SmartRule? get rule;

  /// Initial members for a static playlist, in order. Invalid with `smart`. 
  @BuiltValueField(wireName: r'itemPids')
  BuiltList<String>? get itemPids;

  PlaylistCreate._();

  factory PlaylistCreate([void updates(PlaylistCreateBuilder b)]) = _$PlaylistCreate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaylistCreateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaylistCreate> get serializer => _$PlaylistCreateSerializer();
}

class _$PlaylistCreateSerializer implements PrimitiveSerializer<PlaylistCreate> {
  @override
  final Iterable<Type> types = const [PlaylistCreate, _$PlaylistCreate];

  @override
  final String wireName = r'PlaylistCreate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaylistCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(String),
    );
    if (object.visibility != null) {
      yield r'visibility';
      yield serializers.serialize(
        object.visibility,
        specifiedType: const FullType(String),
      );
    }
    if (object.rule != null) {
      yield r'rule';
      yield serializers.serialize(
        object.rule,
        specifiedType: const FullType(SmartRule),
      );
    }
    if (object.itemPids != null) {
      yield r'itemPids';
      yield serializers.serialize(
        object.itemPids,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaylistCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaylistCreateBuilder result,
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
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.kind = valueDes;
          break;
        case r'visibility':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.visibility = valueDes;
          break;
        case r'rule':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SmartRule),
          ) as SmartRule;
          result.rule.replace(valueDes);
          break;
        case r'itemPids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.itemPids.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaylistCreate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaylistCreateBuilder();
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

