//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/write_back_failure.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/metadata_commit_part.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'metadata_commit_result.g.dart';

/// What a compound commit did, part by part in execution order.  Read `parts` rather than the status code: a refusal is a 200 here, and the accumulated `writeBackFailures` and `warnings` belong to the parts that committed before it.  There is no `resultingAlbumPid`. Editing a release-keying field on one item can still regroup its release, exactly as `editItemMetadata` can, and neither operation reports where it landed; only the bulk edit does, because only its caller (the release workbench) is following a whole release across the move. 
///
/// Properties:
/// * [parts] - One entry per part the request carried, in the order they were run. A part after a refused one is present and `skipped`, so the list always accounts for the whole request. 
/// * [writeBackFailures] - Files whose tags could not be updated, merged across every part and deduplicated: several parts can report the same file for the same reason, and each line is for a person to read once. 
/// * [warnings] - The parts' non-fatal notes, merged: typed drop warnings from the tag library, roles without a tag form, malformed LRC lines skipped. 
@BuiltValue()
abstract class MetadataCommitResult implements Built<MetadataCommitResult, MetadataCommitResultBuilder> {
  /// One entry per part the request carried, in the order they were run. A part after a refused one is present and `skipped`, so the list always accounts for the whole request. 
  @BuiltValueField(wireName: r'parts')
  BuiltList<MetadataCommitPart> get parts;

  /// Files whose tags could not be updated, merged across every part and deduplicated: several parts can report the same file for the same reason, and each line is for a person to read once. 
  @BuiltValueField(wireName: r'writeBackFailures')
  BuiltList<WriteBackFailure>? get writeBackFailures;

  /// The parts' non-fatal notes, merged: typed drop warnings from the tag library, roles without a tag form, malformed LRC lines skipped. 
  @BuiltValueField(wireName: r'warnings')
  BuiltList<String>? get warnings;

  MetadataCommitResult._();

  factory MetadataCommitResult([void updates(MetadataCommitResultBuilder b)]) = _$MetadataCommitResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MetadataCommitResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MetadataCommitResult> get serializer => _$MetadataCommitResultSerializer();
}

class _$MetadataCommitResultSerializer implements PrimitiveSerializer<MetadataCommitResult> {
  @override
  final Iterable<Type> types = const [MetadataCommitResult, _$MetadataCommitResult];

  @override
  final String wireName = r'MetadataCommitResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MetadataCommitResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'parts';
    yield serializers.serialize(
      object.parts,
      specifiedType: const FullType(BuiltList, [FullType(MetadataCommitPart)]),
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
  }

  @override
  Object serialize(
    Serializers serializers,
    MetadataCommitResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MetadataCommitResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'parts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(MetadataCommitPart)]),
          ) as BuiltList<MetadataCommitPart>;
          result.parts.replace(valueDes);
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MetadataCommitResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MetadataCommitResultBuilder();
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

