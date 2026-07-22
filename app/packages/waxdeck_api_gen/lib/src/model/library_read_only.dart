//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'library_read_only.g.dart';

/// A library's read-only flag.
///
/// Properties:
/// * [readOnly] - Whether the library refuses writes.
/// * [libraryPid] - The library (response only).
@BuiltValue()
abstract class LibraryReadOnly implements Built<LibraryReadOnly, LibraryReadOnlyBuilder> {
  /// Whether the library refuses writes.
  @BuiltValueField(wireName: r'readOnly')
  bool get readOnly;

  /// The library (response only).
  @BuiltValueField(wireName: r'libraryPid')
  String? get libraryPid;

  LibraryReadOnly._();

  factory LibraryReadOnly([void updates(LibraryReadOnlyBuilder b)]) = _$LibraryReadOnly;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LibraryReadOnlyBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LibraryReadOnly> get serializer => _$LibraryReadOnlySerializer();
}

class _$LibraryReadOnlySerializer implements PrimitiveSerializer<LibraryReadOnly> {
  @override
  final Iterable<Type> types = const [LibraryReadOnly, _$LibraryReadOnly];

  @override
  final String wireName = r'LibraryReadOnly';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LibraryReadOnly object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'readOnly';
    yield serializers.serialize(
      object.readOnly,
      specifiedType: const FullType(bool),
    );
    if (object.libraryPid != null) {
      yield r'libraryPid';
      yield serializers.serialize(
        object.libraryPid,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    LibraryReadOnly object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LibraryReadOnlyBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'readOnly':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.readOnly = valueDes;
          break;
        case r'libraryPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.libraryPid = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LibraryReadOnly deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LibraryReadOnlyBuilder();
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

