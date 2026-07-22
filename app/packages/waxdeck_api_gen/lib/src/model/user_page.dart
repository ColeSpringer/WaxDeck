//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/user_account.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'user_page.g.dart';

/// One keyset-paginated page of accounts.
///
/// Properties:
/// * [users] - Accounts, in the endpoint's documented order (the account list orders by username; the signup request queue oldest first). 
/// * [nextCursor] - Opaque cursor for the next page. Absent on the last page.
@BuiltValue()
abstract class UserPage implements Built<UserPage, UserPageBuilder> {
  /// Accounts, in the endpoint's documented order (the account list orders by username; the signup request queue oldest first). 
  @BuiltValueField(wireName: r'users')
  BuiltList<UserAccount> get users;

  /// Opaque cursor for the next page. Absent on the last page.
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  UserPage._();

  factory UserPage([void updates(UserPageBuilder b)]) = _$UserPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UserPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UserPage> get serializer => _$UserPageSerializer();
}

class _$UserPageSerializer implements PrimitiveSerializer<UserPage> {
  @override
  final Iterable<Type> types = const [UserPage, _$UserPage];

  @override
  final String wireName = r'UserPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UserPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'users';
    yield serializers.serialize(
      object.users,
      specifiedType: const FullType(BuiltList, [FullType(UserAccount)]),
    );
    if (object.nextCursor != null) {
      yield r'nextCursor';
      yield serializers.serialize(
        object.nextCursor,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    UserPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UserPageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'users':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(UserAccount)]),
          ) as BuiltList<UserAccount>;
          result.users.replace(valueDes);
          break;
        case r'nextCursor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nextCursor = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UserPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UserPageBuilder();
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

