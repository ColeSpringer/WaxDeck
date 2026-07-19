//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/smart_rule.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playlist_update.g.dart';

/// Update a playlist. Omitted properties stay unchanged; `rule` applies only to smart playlists and reissues the pid. 
///
/// Properties:
/// * [name] - New display name.
/// * [visibility] - `private` or `shared`.
/// * [rule] 
@BuiltValue()
abstract class PlaylistUpdate implements Built<PlaylistUpdate, PlaylistUpdateBuilder> {
  /// New display name.
  @BuiltValueField(wireName: r'name')
  String? get name;

  /// `private` or `shared`.
  @BuiltValueField(wireName: r'visibility')
  String? get visibility;

  @BuiltValueField(wireName: r'rule')
  SmartRule? get rule;

  PlaylistUpdate._();

  factory PlaylistUpdate([void updates(PlaylistUpdateBuilder b)]) = _$PlaylistUpdate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaylistUpdateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaylistUpdate> get serializer => _$PlaylistUpdateSerializer();
}

class _$PlaylistUpdateSerializer implements PrimitiveSerializer<PlaylistUpdate> {
  @override
  final Iterable<Type> types = const [PlaylistUpdate, _$PlaylistUpdate];

  @override
  final String wireName = r'PlaylistUpdate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaylistUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType(String),
      );
    }
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
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaylistUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaylistUpdateBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaylistUpdate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaylistUpdateBuilder();
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

