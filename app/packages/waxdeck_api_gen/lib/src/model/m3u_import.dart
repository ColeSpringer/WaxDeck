//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'm3u_import.g.dart';

/// An M3U8 document to import as a static playlist.
///
/// Properties:
/// * [name] - Name for the created playlist.
/// * [visibility] - `private` (default) or `shared`.
/// * [content] - The M3U8 document text.
@BuiltValue()
abstract class M3uImport implements Built<M3uImport, M3uImportBuilder> {
  /// Name for the created playlist.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// `private` (default) or `shared`.
  @BuiltValueField(wireName: r'visibility')
  String? get visibility;

  /// The M3U8 document text.
  @BuiltValueField(wireName: r'content')
  String get content;

  M3uImport._();

  factory M3uImport([void updates(M3uImportBuilder b)]) = _$M3uImport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(M3uImportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<M3uImport> get serializer => _$M3uImportSerializer();
}

class _$M3uImportSerializer implements PrimitiveSerializer<M3uImport> {
  @override
  final Iterable<Type> types = const [M3uImport, _$M3uImport];

  @override
  final String wireName = r'M3uImport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    M3uImport object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.visibility != null) {
      yield r'visibility';
      yield serializers.serialize(
        object.visibility,
        specifiedType: const FullType(String),
      );
    }
    yield r'content';
    yield serializers.serialize(
      object.content,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    M3uImport object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required M3uImportBuilder result,
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
        case r'content':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.content = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  M3uImport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = M3uImportBuilder();
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

