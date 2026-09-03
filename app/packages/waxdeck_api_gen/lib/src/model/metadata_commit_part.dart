//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/error.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'metadata_commit_part.g.dart';

/// One part of a compound commit and what became of it.
///
/// Properties:
/// * [part_] - Which staged part this entry is about. `lyrics` covers both replacing them and clearing them. 
/// * [detail] - Which one, where the part repeats: the role for `credit`, the tag key for `tagSet` and `tagRemove`. Absent otherwise. 
/// * [status] - `committed` means the catalog write landed (write-back trouble rides `writeBackFailures`, never this). `refused` is the one part that stopped the commit, with its `refusal`. `skipped` is a part after that one, which was never attempted, or a `credit` role that shared an atomic batch with the refused one. 
/// * [refusal] 
@BuiltValue()
abstract class MetadataCommitPart implements Built<MetadataCommitPart, MetadataCommitPartBuilder> {
  /// Which staged part this entry is about. `lyrics` covers both replacing them and clearing them. 
  @BuiltValueField(wireName: r'part')
  MetadataCommitPartPart_Enum get part_;
  // enum part_Enum {  fields,  credit,  lyrics,  chapters,  tagSet,  tagRemove,  releaseStatus,  };

  /// Which one, where the part repeats: the role for `credit`, the tag key for `tagSet` and `tagRemove`. Absent otherwise. 
  @BuiltValueField(wireName: r'detail')
  String? get detail;

  /// `committed` means the catalog write landed (write-back trouble rides `writeBackFailures`, never this). `refused` is the one part that stopped the commit, with its `refusal`. `skipped` is a part after that one, which was never attempted, or a `credit` role that shared an atomic batch with the refused one. 
  @BuiltValueField(wireName: r'status')
  MetadataCommitPartStatusEnum get status;
  // enum statusEnum {  committed,  refused,  skipped,  };

  @BuiltValueField(wireName: r'refusal')
  Error? get refusal;

  MetadataCommitPart._();

  factory MetadataCommitPart([void updates(MetadataCommitPartBuilder b)]) = _$MetadataCommitPart;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MetadataCommitPartBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MetadataCommitPart> get serializer => _$MetadataCommitPartSerializer();
}

class _$MetadataCommitPartSerializer implements PrimitiveSerializer<MetadataCommitPart> {
  @override
  final Iterable<Type> types = const [MetadataCommitPart, _$MetadataCommitPart];

  @override
  final String wireName = r'MetadataCommitPart';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MetadataCommitPart object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'part';
    yield serializers.serialize(
      object.part_,
      specifiedType: const FullType(MetadataCommitPartPart_Enum),
    );
    if (object.detail != null) {
      yield r'detail';
      yield serializers.serialize(
        object.detail,
        specifiedType: const FullType(String),
      );
    }
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(MetadataCommitPartStatusEnum),
    );
    if (object.refusal != null) {
      yield r'refusal';
      yield serializers.serialize(
        object.refusal,
        specifiedType: const FullType(Error),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    MetadataCommitPart object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MetadataCommitPartBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'part':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MetadataCommitPartPart_Enum),
          ) as MetadataCommitPartPart_Enum;
          result.part_ = valueDes;
          break;
        case r'detail':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.detail = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MetadataCommitPartStatusEnum),
          ) as MetadataCommitPartStatusEnum;
          result.status = valueDes;
          break;
        case r'refusal':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Error),
          ) as Error;
          result.refusal.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MetadataCommitPart deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MetadataCommitPartBuilder();
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

class MetadataCommitPartPart_Enum extends EnumClass {

  /// Which staged part this entry is about. `lyrics` covers both replacing them and clearing them. 
  @BuiltValueEnumConst(wireName: r'fields')
  static const MetadataCommitPartPart_Enum fields = _$metadataCommitPartPartEnum_fields;
  /// Which staged part this entry is about. `lyrics` covers both replacing them and clearing them. 
  @BuiltValueEnumConst(wireName: r'credit')
  static const MetadataCommitPartPart_Enum credit = _$metadataCommitPartPartEnum_credit;
  /// Which staged part this entry is about. `lyrics` covers both replacing them and clearing them. 
  @BuiltValueEnumConst(wireName: r'lyrics')
  static const MetadataCommitPartPart_Enum lyrics = _$metadataCommitPartPartEnum_lyrics;
  /// Which staged part this entry is about. `lyrics` covers both replacing them and clearing them. 
  @BuiltValueEnumConst(wireName: r'chapters')
  static const MetadataCommitPartPart_Enum chapters = _$metadataCommitPartPartEnum_chapters;
  /// Which staged part this entry is about. `lyrics` covers both replacing them and clearing them. 
  @BuiltValueEnumConst(wireName: r'tagSet')
  static const MetadataCommitPartPart_Enum tagSet = _$metadataCommitPartPartEnum_tagSet;
  /// Which staged part this entry is about. `lyrics` covers both replacing them and clearing them. 
  @BuiltValueEnumConst(wireName: r'tagRemove')
  static const MetadataCommitPartPart_Enum tagRemove = _$metadataCommitPartPartEnum_tagRemove;
  /// Which staged part this entry is about. `lyrics` covers both replacing them and clearing them. 
  @BuiltValueEnumConst(wireName: r'releaseStatus')
  static const MetadataCommitPartPart_Enum releaseStatus = _$metadataCommitPartPartEnum_releaseStatus;
  /// Which staged part this entry is about. `lyrics` covers both replacing them and clearing them. 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const MetadataCommitPartPart_Enum unknownDefaultOpenApi = _$metadataCommitPartPartEnum_unknownDefaultOpenApi;

  static Serializer<MetadataCommitPartPart_Enum> get serializer => _$metadataCommitPartPartEnumSerializer;

  const MetadataCommitPartPart_Enum._(String name): super(name);

  static BuiltSet<MetadataCommitPartPart_Enum> get values => _$metadataCommitPartPartEnumValues;
  static MetadataCommitPartPart_Enum valueOf(String name) => _$metadataCommitPartPartEnumValueOf(name);
}

class MetadataCommitPartStatusEnum extends EnumClass {

  /// `committed` means the catalog write landed (write-back trouble rides `writeBackFailures`, never this). `refused` is the one part that stopped the commit, with its `refusal`. `skipped` is a part after that one, which was never attempted, or a `credit` role that shared an atomic batch with the refused one. 
  @BuiltValueEnumConst(wireName: r'committed')
  static const MetadataCommitPartStatusEnum committed = _$metadataCommitPartStatusEnum_committed;
  /// `committed` means the catalog write landed (write-back trouble rides `writeBackFailures`, never this). `refused` is the one part that stopped the commit, with its `refusal`. `skipped` is a part after that one, which was never attempted, or a `credit` role that shared an atomic batch with the refused one. 
  @BuiltValueEnumConst(wireName: r'refused')
  static const MetadataCommitPartStatusEnum refused = _$metadataCommitPartStatusEnum_refused;
  /// `committed` means the catalog write landed (write-back trouble rides `writeBackFailures`, never this). `refused` is the one part that stopped the commit, with its `refusal`. `skipped` is a part after that one, which was never attempted, or a `credit` role that shared an atomic batch with the refused one. 
  @BuiltValueEnumConst(wireName: r'skipped')
  static const MetadataCommitPartStatusEnum skipped = _$metadataCommitPartStatusEnum_skipped;
  /// `committed` means the catalog write landed (write-back trouble rides `writeBackFailures`, never this). `refused` is the one part that stopped the commit, with its `refusal`. `skipped` is a part after that one, which was never attempted, or a `credit` role that shared an atomic batch with the refused one. 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const MetadataCommitPartStatusEnum unknownDefaultOpenApi = _$metadataCommitPartStatusEnum_unknownDefaultOpenApi;

  static Serializer<MetadataCommitPartStatusEnum> get serializer => _$metadataCommitPartStatusEnumSerializer;

  const MetadataCommitPartStatusEnum._(String name): super(name);

  static BuiltSet<MetadataCommitPartStatusEnum> get values => _$metadataCommitPartStatusEnumValues;
  static MetadataCommitPartStatusEnum valueOf(String name) => _$metadataCommitPartStatusEnumValueOf(name);
}

