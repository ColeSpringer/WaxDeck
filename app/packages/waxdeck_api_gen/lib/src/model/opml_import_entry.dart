//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'opml_import_entry.g.dart';

/// The import outcome for one OPML feed entry.
///
/// Properties:
/// * [feedUrl] - The feed URL from the document.
/// * [title] - The show title, when the feed resolved.
/// * [pid] - The subscribed show's PID, when the feed resolved.
/// * [error] - Why this feed failed to subscribe, when it did.
@BuiltValue()
abstract class OpmlImportEntry implements Built<OpmlImportEntry, OpmlImportEntryBuilder> {
  /// The feed URL from the document.
  @BuiltValueField(wireName: r'feedUrl')
  String get feedUrl;

  /// The show title, when the feed resolved.
  @BuiltValueField(wireName: r'title')
  String? get title;

  /// The subscribed show's PID, when the feed resolved.
  @BuiltValueField(wireName: r'pid')
  String? get pid;

  /// Why this feed failed to subscribe, when it did.
  @BuiltValueField(wireName: r'error')
  String? get error;

  OpmlImportEntry._();

  factory OpmlImportEntry([void updates(OpmlImportEntryBuilder b)]) = _$OpmlImportEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OpmlImportEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OpmlImportEntry> get serializer => _$OpmlImportEntrySerializer();
}

class _$OpmlImportEntrySerializer implements PrimitiveSerializer<OpmlImportEntry> {
  @override
  final Iterable<Type> types = const [OpmlImportEntry, _$OpmlImportEntry];

  @override
  final String wireName = r'OpmlImportEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OpmlImportEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'feedUrl';
    yield serializers.serialize(
      object.feedUrl,
      specifiedType: const FullType(String),
    );
    if (object.title != null) {
      yield r'title';
      yield serializers.serialize(
        object.title,
        specifiedType: const FullType(String),
      );
    }
    if (object.pid != null) {
      yield r'pid';
      yield serializers.serialize(
        object.pid,
        specifiedType: const FullType(String),
      );
    }
    if (object.error != null) {
      yield r'error';
      yield serializers.serialize(
        object.error,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    OpmlImportEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OpmlImportEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'feedUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.feedUrl = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.error = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OpmlImportEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OpmlImportEntryBuilder();
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

