//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'feed_person.g.dart';

/// One person credited in a feed, from a `<podcast:person>` tag at the show or episode level. 
///
/// Properties:
/// * [name] - The person's name.
/// * [role] - Their role, lowercased as the feed published it (`host`, `guest`, `producer`, ...). Open set; an absent role reads as `host`, the podcast namespace default. 
/// * [group] - The role's grouping, lowercased (`cast`, `writing`, ...), when the feed declares one. 
/// * [img] - Portrait image URL, when the feed declares one.
/// * [href] - Profile or information URL, when the feed declares one.
@BuiltValue()
abstract class FeedPerson implements Built<FeedPerson, FeedPersonBuilder> {
  /// The person's name.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Their role, lowercased as the feed published it (`host`, `guest`, `producer`, ...). Open set; an absent role reads as `host`, the podcast namespace default. 
  @BuiltValueField(wireName: r'role')
  String? get role;

  /// The role's grouping, lowercased (`cast`, `writing`, ...), when the feed declares one. 
  @BuiltValueField(wireName: r'group')
  String? get group;

  /// Portrait image URL, when the feed declares one.
  @BuiltValueField(wireName: r'img')
  String? get img;

  /// Profile or information URL, when the feed declares one.
  @BuiltValueField(wireName: r'href')
  String? get href;

  FeedPerson._();

  factory FeedPerson([void updates(FeedPersonBuilder b)]) = _$FeedPerson;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(FeedPersonBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<FeedPerson> get serializer => _$FeedPersonSerializer();
}

class _$FeedPersonSerializer implements PrimitiveSerializer<FeedPerson> {
  @override
  final Iterable<Type> types = const [FeedPerson, _$FeedPerson];

  @override
  final String wireName = r'FeedPerson';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FeedPerson object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.role != null) {
      yield r'role';
      yield serializers.serialize(
        object.role,
        specifiedType: const FullType(String),
      );
    }
    if (object.group != null) {
      yield r'group';
      yield serializers.serialize(
        object.group,
        specifiedType: const FullType(String),
      );
    }
    if (object.img != null) {
      yield r'img';
      yield serializers.serialize(
        object.img,
        specifiedType: const FullType(String),
      );
    }
    if (object.href != null) {
      yield r'href';
      yield serializers.serialize(
        object.href,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    FeedPerson object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required FeedPersonBuilder result,
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
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.role = valueDes;
          break;
        case r'group':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.group = valueDes;
          break;
        case r'img':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.img = valueDes;
          break;
        case r'href':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.href = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  FeedPerson deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = FeedPersonBuilder();
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

