//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/m3u_preview_entry.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'm3u_preview.g.dart';

/// How every path line of an M3U8 document matches. The three counts add up to the lines in `entries`. 
///
/// Properties:
/// * [matched] - Lines that become entries of the playlist.
/// * [merged] - Lines naming the item of the line before them through a different path to it (another of its files, or another spelling of the same file), which add no entry. 
/// * [unmatched] - Lines naming nothing the caller can see.
/// * [entries] - Every path line, in document order.
@BuiltValue()
abstract class M3uPreview implements Built<M3uPreview, M3uPreviewBuilder> {
  /// Lines that become entries of the playlist.
  @BuiltValueField(wireName: r'matched')
  int get matched;

  /// Lines naming the item of the line before them through a different path to it (another of its files, or another spelling of the same file), which add no entry. 
  @BuiltValueField(wireName: r'merged')
  int get merged;

  /// Lines naming nothing the caller can see.
  @BuiltValueField(wireName: r'unmatched')
  int get unmatched;

  /// Every path line, in document order.
  @BuiltValueField(wireName: r'entries')
  BuiltList<M3uPreviewEntry> get entries;

  M3uPreview._();

  factory M3uPreview([void updates(M3uPreviewBuilder b)]) = _$M3uPreview;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(M3uPreviewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<M3uPreview> get serializer => _$M3uPreviewSerializer();
}

class _$M3uPreviewSerializer implements PrimitiveSerializer<M3uPreview> {
  @override
  final Iterable<Type> types = const [M3uPreview, _$M3uPreview];

  @override
  final String wireName = r'M3uPreview';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    M3uPreview object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'matched';
    yield serializers.serialize(
      object.matched,
      specifiedType: const FullType(int),
    );
    yield r'merged';
    yield serializers.serialize(
      object.merged,
      specifiedType: const FullType(int),
    );
    yield r'unmatched';
    yield serializers.serialize(
      object.unmatched,
      specifiedType: const FullType(int),
    );
    yield r'entries';
    yield serializers.serialize(
      object.entries,
      specifiedType: const FullType(BuiltList, [FullType(M3uPreviewEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    M3uPreview object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required M3uPreviewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'matched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.matched = valueDes;
          break;
        case r'merged':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.merged = valueDes;
          break;
        case r'unmatched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.unmatched = valueDes;
          break;
        case r'entries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(M3uPreviewEntry)]),
          ) as BuiltList<M3uPreviewEntry>;
          result.entries.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  M3uPreview deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = M3uPreviewBuilder();
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


