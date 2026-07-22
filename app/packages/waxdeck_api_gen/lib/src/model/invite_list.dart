//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/invite.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'invite_list.g.dart';

/// All invites.
///
/// Properties:
/// * [invites] - Invites, newest first.
@BuiltValue()
abstract class InviteList implements Built<InviteList, InviteListBuilder> {
  /// Invites, newest first.
  @BuiltValueField(wireName: r'invites')
  BuiltList<Invite> get invites;

  InviteList._();

  factory InviteList([void updates(InviteListBuilder b)]) = _$InviteList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InviteListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InviteList> get serializer => _$InviteListSerializer();
}

class _$InviteListSerializer implements PrimitiveSerializer<InviteList> {
  @override
  final Iterable<Type> types = const [InviteList, _$InviteList];

  @override
  final String wireName = r'InviteList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InviteList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'invites';
    yield serializers.serialize(
      object.invites,
      specifiedType: const FullType(BuiltList, [FullType(Invite)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    InviteList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InviteListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'invites':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Invite)]),
          ) as BuiltList<Invite>;
          result.invites.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InviteList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InviteListBuilder();
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

