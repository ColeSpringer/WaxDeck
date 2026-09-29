//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/smart_rule.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/nsp_gap.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'nsp_report.g.dart';

/// What one NSP mapping could not carry: `gaps` block a strict conversion and are what `partial=true` drops; `notes` block nothing. `rule` is what a partial conversion keeps, present only when there are `gaps` and it would keep something; an export report also carries `ruleHash`. 
///
/// Properties:
/// * [direction] - Which way the mapping ran, and so whose vocabulary the gaps' `field` and `op` are written in. 
/// * [gaps] - Losses that refuse the strict conversion.  Deduplicated by what a gap names (its `code`, `field`, `op`, `key`, `mode` and `value`) and capped: a rule or a document repeating one problem is one problem, and `path` names the first place it was found. The strict refusal's message is composed from this same list, each sentence once, so a refusal and a report never disagree about what is wrong. 
/// * [notes] - Losses that refuse nothing. Deduplicated and capped the same way. 
/// * [truncated] - Present and true when `gaps` or `notes` stopped at the cap, so there is more than they list. 
/// * [ruleHash] - Export only: names the rule this report was read from, to pass back as the export's `ruleHash`. 
/// * [rule] 
@BuiltValue()
abstract class NspReport implements Built<NspReport, NspReportBuilder> {
  /// Which way the mapping ran, and so whose vocabulary the gaps' `field` and `op` are written in. 
  @BuiltValueField(wireName: r'direction')
  NspReportDirectionEnum get direction;
  // enum directionEnum {  export,  import,  };

  /// Losses that refuse the strict conversion.  Deduplicated by what a gap names (its `code`, `field`, `op`, `key`, `mode` and `value`) and capped: a rule or a document repeating one problem is one problem, and `path` names the first place it was found. The strict refusal's message is composed from this same list, each sentence once, so a refusal and a report never disagree about what is wrong. 
  @BuiltValueField(wireName: r'gaps')
  BuiltList<NspGap>? get gaps;

  /// Losses that refuse nothing. Deduplicated and capped the same way. 
  @BuiltValueField(wireName: r'notes')
  BuiltList<NspGap>? get notes;

  /// Present and true when `gaps` or `notes` stopped at the cap, so there is more than they list. 
  @BuiltValueField(wireName: r'truncated')
  bool? get truncated;

  /// Export only: names the rule this report was read from, to pass back as the export's `ruleHash`. 
  @BuiltValueField(wireName: r'ruleHash')
  String? get ruleHash;

  @BuiltValueField(wireName: r'rule')
  SmartRule? get rule;

  NspReport._();

  factory NspReport([void updates(NspReportBuilder b)]) = _$NspReport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NspReportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NspReport> get serializer => _$NspReportSerializer();
}

class _$NspReportSerializer implements PrimitiveSerializer<NspReport> {
  @override
  final Iterable<Type> types = const [NspReport, _$NspReport];

  @override
  final String wireName = r'NspReport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NspReport object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'direction';
    yield serializers.serialize(
      object.direction,
      specifiedType: const FullType(NspReportDirectionEnum),
    );
    if (object.gaps != null) {
      yield r'gaps';
      yield serializers.serialize(
        object.gaps,
        specifiedType: const FullType(BuiltList, [FullType(NspGap)]),
      );
    }
    if (object.notes != null) {
      yield r'notes';
      yield serializers.serialize(
        object.notes,
        specifiedType: const FullType(BuiltList, [FullType(NspGap)]),
      );
    }
    if (object.truncated != null) {
      yield r'truncated';
      yield serializers.serialize(
        object.truncated,
        specifiedType: const FullType(bool),
      );
    }
    if (object.ruleHash != null) {
      yield r'ruleHash';
      yield serializers.serialize(
        object.ruleHash,
        specifiedType: const FullType(String),
      );
    }
    if (object.rule != null) {
      yield r'rule';
      yield serializers.serialize(
        object.rule,
        specifiedType: const FullType(SmartRule),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    NspReport object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NspReportBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'direction':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(NspReportDirectionEnum),
          ) as NspReportDirectionEnum;
          result.direction = valueDes;
          break;
        case r'gaps':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(NspGap)]),
          ) as BuiltList<NspGap>?;
          if (valueDes == null) continue;
          result.gaps.replace(valueDes);
          break;
        case r'notes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(NspGap)]),
          ) as BuiltList<NspGap>?;
          if (valueDes == null) continue;
          result.notes.replace(valueDes);
          break;
        case r'truncated':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.truncated = valueDes;
          break;
        case r'ruleHash':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.ruleHash = valueDes;
          break;
        case r'rule':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(SmartRule),
          ) as SmartRule?;
          if (valueDes == null) continue;
          result.rule.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NspReport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NspReportBuilder();
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


/// Which way the mapping ran, and so whose vocabulary the gaps' `field` and `op` are written in. 
class NspReportDirectionEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'export')
  static const NspReportDirectionEnum export_ = _$nspReportDirectionEnum_export_;
  @BuiltValueEnumConst(wireName: r'import')
  static const NspReportDirectionEnum import_ = _$nspReportDirectionEnum_import_;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const NspReportDirectionEnum unknownDefaultOpenApi = _$nspReportDirectionEnum_unknownDefaultOpenApi;

  static Serializer<NspReportDirectionEnum> get serializer => _$nspReportDirectionEnumSerializer;

  const NspReportDirectionEnum._(String name): super(name);

  static BuiltSet<NspReportDirectionEnum> get values => _$nspReportDirectionEnumValues;
  static NspReportDirectionEnum valueOf(String name) => _$nspReportDirectionEnumValueOf(name);
}

