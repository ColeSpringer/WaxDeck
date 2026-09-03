//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/write_back_failure.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'metadata_edit_result.g.dart';

/// The outcome of a metadata mutation. The catalog write succeeded whenever this shape returns; write-back trouble and drop warnings ride along instead of failing the edit. 
///
/// Properties:
/// * [applied] - Always true; the catalog committed.
/// * [writeBackFailures] - Files whose tags could not be updated.
/// * [warnings] - Non-fatal notes: typed drop warnings from the tag library (a format refusing embedded synced lyrics, a chapter cap), roles without a tag form, malformed LRC lines skipped. 
/// * [mergedInto] - The surviving entity when the edit re-keyed this one onto a key another entity already held, which only an `mbid` clear does. The named entity is gone; talk about this pid instead. 
/// * [movedAlbums] - Albums that left the edited release group because the clear re-keyed it and their titles put them in a group of their own. Their members are no longer reachable through the edited group. 
@BuiltValue()
abstract class MetadataEditResult implements Built<MetadataEditResult, MetadataEditResultBuilder> {
  /// Always true; the catalog committed.
  @BuiltValueField(wireName: r'applied')
  bool get applied;

  /// Files whose tags could not be updated.
  @BuiltValueField(wireName: r'writeBackFailures')
  BuiltList<WriteBackFailure>? get writeBackFailures;

  /// Non-fatal notes: typed drop warnings from the tag library (a format refusing embedded synced lyrics, a chapter cap), roles without a tag form, malformed LRC lines skipped. 
  @BuiltValueField(wireName: r'warnings')
  BuiltList<String>? get warnings;

  /// The surviving entity when the edit re-keyed this one onto a key another entity already held, which only an `mbid` clear does. The named entity is gone; talk about this pid instead. 
  @BuiltValueField(wireName: r'mergedInto')
  String? get mergedInto;

  /// Albums that left the edited release group because the clear re-keyed it and their titles put them in a group of their own. Their members are no longer reachable through the edited group. 
  @BuiltValueField(wireName: r'movedAlbums')
  BuiltList<String>? get movedAlbums;

  MetadataEditResult._();

  factory MetadataEditResult([void updates(MetadataEditResultBuilder b)]) = _$MetadataEditResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MetadataEditResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MetadataEditResult> get serializer => _$MetadataEditResultSerializer();
}

class _$MetadataEditResultSerializer implements PrimitiveSerializer<MetadataEditResult> {
  @override
  final Iterable<Type> types = const [MetadataEditResult, _$MetadataEditResult];

  @override
  final String wireName = r'MetadataEditResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MetadataEditResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'applied';
    yield serializers.serialize(
      object.applied,
      specifiedType: const FullType(bool),
    );
    if (object.writeBackFailures != null) {
      yield r'writeBackFailures';
      yield serializers.serialize(
        object.writeBackFailures,
        specifiedType: const FullType(BuiltList, [FullType(WriteBackFailure)]),
      );
    }
    if (object.warnings != null) {
      yield r'warnings';
      yield serializers.serialize(
        object.warnings,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.mergedInto != null) {
      yield r'mergedInto';
      yield serializers.serialize(
        object.mergedInto,
        specifiedType: const FullType(String),
      );
    }
    if (object.movedAlbums != null) {
      yield r'movedAlbums';
      yield serializers.serialize(
        object.movedAlbums,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    MetadataEditResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MetadataEditResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'applied':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.applied = valueDes;
          break;
        case r'writeBackFailures':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(WriteBackFailure)]),
          ) as BuiltList<WriteBackFailure>;
          result.writeBackFailures.replace(valueDes);
          break;
        case r'warnings':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.warnings.replace(valueDes);
          break;
        case r'mergedInto':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.mergedInto = valueDes;
          break;
        case r'movedAlbums':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.movedAlbums.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MetadataEditResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MetadataEditResultBuilder();
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

