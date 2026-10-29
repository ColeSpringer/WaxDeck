//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/item_summary.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'm3u_preview_entry.g.dart';

/// One path line and what it matched; `item` is present on a `matched` or `merged` line. 
///
/// Properties:
/// * [path] - The line's path, as the document gives it.
/// * [outcome] - `matched`, `merged` (the item of the line before it, through a different path to it: another of its files, or another spelling of the same file) or `unmatched`. The same path given twice in a row is `matched` both times. 
/// * [item] 
@BuiltValue()
abstract class M3uPreviewEntry implements Built<M3uPreviewEntry, M3uPreviewEntryBuilder> {
  /// The line's path, as the document gives it.
  @BuiltValueField(wireName: r'path')
  String get path;

  /// `matched`, `merged` (the item of the line before it, through a different path to it: another of its files, or another spelling of the same file) or `unmatched`. The same path given twice in a row is `matched` both times. 
  @BuiltValueField(wireName: r'outcome')
  M3uPreviewEntryOutcomeEnum get outcome;
  // enum outcomeEnum {  matched,  merged,  unmatched,  };

  @BuiltValueField(wireName: r'item')
  ItemSummary? get item;

  M3uPreviewEntry._();

  factory M3uPreviewEntry([void updates(M3uPreviewEntryBuilder b)]) = _$M3uPreviewEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(M3uPreviewEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<M3uPreviewEntry> get serializer => _$M3uPreviewEntrySerializer();
}

class _$M3uPreviewEntrySerializer implements PrimitiveSerializer<M3uPreviewEntry> {
  @override
  final Iterable<Type> types = const [M3uPreviewEntry, _$M3uPreviewEntry];

  @override
  final String wireName = r'M3uPreviewEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    M3uPreviewEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'path';
    yield serializers.serialize(
      object.path,
      specifiedType: const FullType(String),
    );
    yield r'outcome';
    yield serializers.serialize(
      object.outcome,
      specifiedType: const FullType(M3uPreviewEntryOutcomeEnum),
    );
    if (object.item != null) {
      yield r'item';
      yield serializers.serialize(
        object.item,
        specifiedType: const FullType(ItemSummary),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    M3uPreviewEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required M3uPreviewEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.path = valueDes;
          break;
        case r'outcome':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(M3uPreviewEntryOutcomeEnum),
          ) as M3uPreviewEntryOutcomeEnum;
          result.outcome = valueDes;
          break;
        case r'item':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(ItemSummary),
          ) as ItemSummary?;
          if (valueDes == null) continue;
          result.item = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  M3uPreviewEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = M3uPreviewEntryBuilder();
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


/// `matched`, `merged` (the item of the line before it, through a different path to it: another of its files, or another spelling of the same file) or `unmatched`. The same path given twice in a row is `matched` both times. 
class M3uPreviewEntryOutcomeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'matched')
  static const M3uPreviewEntryOutcomeEnum matched = _$m3uPreviewEntryOutcomeEnum_matched;
  @BuiltValueEnumConst(wireName: r'merged')
  static const M3uPreviewEntryOutcomeEnum merged = _$m3uPreviewEntryOutcomeEnum_merged;
  @BuiltValueEnumConst(wireName: r'unmatched')
  static const M3uPreviewEntryOutcomeEnum unmatched = _$m3uPreviewEntryOutcomeEnum_unmatched;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const M3uPreviewEntryOutcomeEnum unknownDefaultOpenApi = _$m3uPreviewEntryOutcomeEnum_unknownDefaultOpenApi;

  static Serializer<M3uPreviewEntryOutcomeEnum> get serializer => _$m3uPreviewEntryOutcomeEnumSerializer;

  const M3uPreviewEntryOutcomeEnum._(String name): super(name);

  static BuiltSet<M3uPreviewEntryOutcomeEnum> get values => _$m3uPreviewEntryOutcomeEnumValues;
  static M3uPreviewEntryOutcomeEnum valueOf(String name) => _$m3uPreviewEntryOutcomeEnumValueOf(name);
}

