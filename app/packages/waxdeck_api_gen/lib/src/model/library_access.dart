//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'library_access.g.dart';

/// Which libraries an account can see. `all` grants every library including ones added later; `granted` limits visibility to `libraryPids`. Administrators always see everything regardless of this setting. 
///
/// Properties:
/// * [mode] - Access mode.
/// * [libraryPids] - Visible libraries when mode is `granted`; ignored for `all`. 
@BuiltValue()
abstract class LibraryAccess implements Built<LibraryAccess, LibraryAccessBuilder> {
  /// Access mode.
  @BuiltValueField(wireName: r'mode')
  LibraryAccessModeEnum get mode;
  // enum modeEnum {  all,  granted,  };

  /// Visible libraries when mode is `granted`; ignored for `all`. 
  @BuiltValueField(wireName: r'libraryPids')
  BuiltList<String>? get libraryPids;

  LibraryAccess._();

  factory LibraryAccess([void updates(LibraryAccessBuilder b)]) = _$LibraryAccess;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LibraryAccessBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LibraryAccess> get serializer => _$LibraryAccessSerializer();
}

class _$LibraryAccessSerializer implements PrimitiveSerializer<LibraryAccess> {
  @override
  final Iterable<Type> types = const [LibraryAccess, _$LibraryAccess];

  @override
  final String wireName = r'LibraryAccess';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LibraryAccess object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'mode';
    yield serializers.serialize(
      object.mode,
      specifiedType: const FullType(LibraryAccessModeEnum),
    );
    if (object.libraryPids != null) {
      yield r'libraryPids';
      yield serializers.serialize(
        object.libraryPids,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    LibraryAccess object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LibraryAccessBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'mode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LibraryAccessModeEnum),
          ) as LibraryAccessModeEnum;
          result.mode = valueDes;
          break;
        case r'libraryPids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.libraryPids.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LibraryAccess deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LibraryAccessBuilder();
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

class LibraryAccessModeEnum extends EnumClass {

  /// Access mode.
  @BuiltValueEnumConst(wireName: r'all')
  static const LibraryAccessModeEnum all = _$libraryAccessModeEnum_all;
  /// Access mode.
  @BuiltValueEnumConst(wireName: r'granted')
  static const LibraryAccessModeEnum granted = _$libraryAccessModeEnum_granted;

  static Serializer<LibraryAccessModeEnum> get serializer => _$libraryAccessModeEnumSerializer;

  const LibraryAccessModeEnum._(String name): super(name);

  static BuiltSet<LibraryAccessModeEnum> get values => _$libraryAccessModeEnumValues;
  static LibraryAccessModeEnum valueOf(String name) => _$libraryAccessModeEnumValueOf(name);
}

