//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'duplicate_warning.g.dart';

/// The library appears to already contain this audio. A warning, not a refusal: the review decision chooses what happens. 
///
/// Properties:
/// * [itemPid] - The existing item.
/// * [kind] - Evidence level: `content` (byte-identical audio) or `fingerprint` (acoustically the same recording). A string, not a closed enum. 
/// * [title] - The existing item's title.
/// * [artist] - The existing item's artist.
@BuiltValue()
abstract class DuplicateWarning implements Built<DuplicateWarning, DuplicateWarningBuilder> {
  /// The existing item.
  @BuiltValueField(wireName: r'itemPid')
  String get itemPid;

  /// Evidence level: `content` (byte-identical audio) or `fingerprint` (acoustically the same recording). A string, not a closed enum. 
  @BuiltValueField(wireName: r'kind')
  String get kind;

  /// The existing item's title.
  @BuiltValueField(wireName: r'title')
  String? get title;

  /// The existing item's artist.
  @BuiltValueField(wireName: r'artist')
  String? get artist;

  DuplicateWarning._();

  factory DuplicateWarning([void updates(DuplicateWarningBuilder b)]) = _$DuplicateWarning;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DuplicateWarningBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DuplicateWarning> get serializer => _$DuplicateWarningSerializer();
}

class _$DuplicateWarningSerializer implements PrimitiveSerializer<DuplicateWarning> {
  @override
  final Iterable<Type> types = const [DuplicateWarning, _$DuplicateWarning];

  @override
  final String wireName = r'DuplicateWarning';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DuplicateWarning object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'itemPid';
    yield serializers.serialize(
      object.itemPid,
      specifiedType: const FullType(String),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(String),
    );
    if (object.title != null) {
      yield r'title';
      yield serializers.serialize(
        object.title,
        specifiedType: const FullType(String),
      );
    }
    if (object.artist != null) {
      yield r'artist';
      yield serializers.serialize(
        object.artist,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DuplicateWarning object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DuplicateWarningBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'itemPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.itemPid = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.kind = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'artist':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artist = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DuplicateWarning deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DuplicateWarningBuilder();
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

