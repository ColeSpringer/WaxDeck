//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'library_profile.g.dart';

/// The organize profile a managed library is laid out by.
///
/// Properties:
/// * [profile] - A profile name from the organize profiles listing.
@BuiltValue()
abstract class LibraryProfile implements Built<LibraryProfile, LibraryProfileBuilder> {
  /// A profile name from the organize profiles listing.
  @BuiltValueField(wireName: r'profile')
  String get profile;

  LibraryProfile._();

  factory LibraryProfile([void updates(LibraryProfileBuilder b)]) = _$LibraryProfile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LibraryProfileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LibraryProfile> get serializer => _$LibraryProfileSerializer();
}

class _$LibraryProfileSerializer implements PrimitiveSerializer<LibraryProfile> {
  @override
  final Iterable<Type> types = const [LibraryProfile, _$LibraryProfile];

  @override
  final String wireName = r'LibraryProfile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LibraryProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'profile';
    yield serializers.serialize(
      object.profile,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    LibraryProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LibraryProfileBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'profile':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.profile = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LibraryProfile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LibraryProfileBuilder();
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


