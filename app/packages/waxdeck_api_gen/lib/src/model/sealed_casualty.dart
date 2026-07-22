//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'sealed_casualty.g.dart';

/// One credential a key-mismatched restore breaks.
///
/// Properties:
/// * [kind] - What kind of credential: `app-password`, `private-feed`, `scrobble-connection`, or others as integrations grow. An open string. 
/// * [name] - Which one, in user terms (\"Symfonium on the kitchen tablet\", the feed's show title).
@BuiltValue()
abstract class SealedCasualty implements Built<SealedCasualty, SealedCasualtyBuilder> {
  /// What kind of credential: `app-password`, `private-feed`, `scrobble-connection`, or others as integrations grow. An open string. 
  @BuiltValueField(wireName: r'kind')
  String get kind;

  /// Which one, in user terms (\"Symfonium on the kitchen tablet\", the feed's show title).
  @BuiltValueField(wireName: r'name')
  String get name;

  SealedCasualty._();

  factory SealedCasualty([void updates(SealedCasualtyBuilder b)]) = _$SealedCasualty;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SealedCasualtyBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SealedCasualty> get serializer => _$SealedCasualtySerializer();
}

class _$SealedCasualtySerializer implements PrimitiveSerializer<SealedCasualty> {
  @override
  final Iterable<Type> types = const [SealedCasualty, _$SealedCasualty];

  @override
  final String wireName = r'SealedCasualty';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SealedCasualty object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SealedCasualty object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SealedCasualtyBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.kind = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SealedCasualty deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SealedCasualtyBuilder();
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

