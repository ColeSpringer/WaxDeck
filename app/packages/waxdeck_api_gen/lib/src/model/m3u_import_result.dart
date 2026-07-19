//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/playlist.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'm3u_import_result.g.dart';

/// The import outcome.
///
/// Properties:
/// * [playlist] 
/// * [matched] - Entries matched to cataloged items.
/// * [unmatched] - Entries no cataloged item matched.
/// * [unmatchedPaths] - The unmatched entry paths, in document order.
@BuiltValue()
abstract class M3uImportResult implements Built<M3uImportResult, M3uImportResultBuilder> {
  @BuiltValueField(wireName: r'playlist')
  Playlist get playlist;

  /// Entries matched to cataloged items.
  @BuiltValueField(wireName: r'matched')
  int get matched;

  /// Entries no cataloged item matched.
  @BuiltValueField(wireName: r'unmatched')
  int get unmatched;

  /// The unmatched entry paths, in document order.
  @BuiltValueField(wireName: r'unmatchedPaths')
  BuiltList<String>? get unmatchedPaths;

  M3uImportResult._();

  factory M3uImportResult([void updates(M3uImportResultBuilder b)]) = _$M3uImportResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(M3uImportResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<M3uImportResult> get serializer => _$M3uImportResultSerializer();
}

class _$M3uImportResultSerializer implements PrimitiveSerializer<M3uImportResult> {
  @override
  final Iterable<Type> types = const [M3uImportResult, _$M3uImportResult];

  @override
  final String wireName = r'M3uImportResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    M3uImportResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'playlist';
    yield serializers.serialize(
      object.playlist,
      specifiedType: const FullType(Playlist),
    );
    yield r'matched';
    yield serializers.serialize(
      object.matched,
      specifiedType: const FullType(int),
    );
    yield r'unmatched';
    yield serializers.serialize(
      object.unmatched,
      specifiedType: const FullType(int),
    );
    if (object.unmatchedPaths != null) {
      yield r'unmatchedPaths';
      yield serializers.serialize(
        object.unmatchedPaths,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    M3uImportResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required M3uImportResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'playlist':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Playlist),
          ) as Playlist;
          result.playlist.replace(valueDes);
          break;
        case r'matched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.matched = valueDes;
          break;
        case r'unmatched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.unmatched = valueDes;
          break;
        case r'unmatchedPaths':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.unmatchedPaths.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  M3uImportResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = M3uImportResultBuilder();
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

