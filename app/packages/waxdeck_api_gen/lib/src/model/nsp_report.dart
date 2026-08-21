//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/nsp_gap.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'nsp_report.g.dart';

/// What one NSP mapping could not carry. `gaps` block the strict conversion and are what a `partial=true` conversion drops; `notes` are losses that block nothing, so a client mentions them without refusing. Both are empty when the mapping is lossless. 
///
/// Properties:
/// * [direction] - Which way the mapping ran, and so whose vocabulary the gaps' `field` and `op` are written in. 
/// * [gaps] - Losses that refuse the strict conversion.  Deduplicated by `reason` and capped: a rule or a document repeating one problem is one problem, and the row a client draws per entry says nothing new the second time. `path` names the first place the problem was found. The strict refusal's message is composed from this same list, so a refusal and a report never disagree about what is wrong. 
/// * [notes] - Losses that refuse nothing. Deduplicated and capped the same way. 
@BuiltValue()
abstract class NspReport implements Built<NspReport, NspReportBuilder> {
  /// Which way the mapping ran, and so whose vocabulary the gaps' `field` and `op` are written in. 
  @BuiltValueField(wireName: r'direction')
  NspReportDirectionEnum get direction;
  // enum directionEnum {  export,  import,  };

  /// Losses that refuse the strict conversion.  Deduplicated by `reason` and capped: a rule or a document repeating one problem is one problem, and the row a client draws per entry says nothing new the second time. `path` names the first place the problem was found. The strict refusal's message is composed from this same list, so a refusal and a report never disagree about what is wrong. 
  @BuiltValueField(wireName: r'gaps')
  BuiltList<NspGap>? get gaps;

  /// Losses that refuse nothing. Deduplicated and capped the same way. 
  @BuiltValueField(wireName: r'notes')
  BuiltList<NspGap>? get notes;

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
            specifiedType: const FullType(BuiltList, [FullType(NspGap)]),
          ) as BuiltList<NspGap>;
          result.gaps.replace(valueDes);
          break;
        case r'notes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(NspGap)]),
          ) as BuiltList<NspGap>;
          result.notes.replace(valueDes);
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

class NspReportDirectionEnum extends EnumClass {

  /// Which way the mapping ran, and so whose vocabulary the gaps' `field` and `op` are written in. 
  @BuiltValueEnumConst(wireName: r'export')
  static const NspReportDirectionEnum export_ = _$nspReportDirectionEnum_export_;
  /// Which way the mapping ran, and so whose vocabulary the gaps' `field` and `op` are written in. 
  @BuiltValueEnumConst(wireName: r'import')
  static const NspReportDirectionEnum import_ = _$nspReportDirectionEnum_import_;
  /// Which way the mapping ran, and so whose vocabulary the gaps' `field` and `op` are written in. 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const NspReportDirectionEnum unknownDefaultOpenApi = _$nspReportDirectionEnum_unknownDefaultOpenApi;

  static Serializer<NspReportDirectionEnum> get serializer => _$nspReportDirectionEnumSerializer;

  const NspReportDirectionEnum._(String name): super(name);

  static BuiltSet<NspReportDirectionEnum> get values => _$nspReportDirectionEnumValues;
  static NspReportDirectionEnum valueOf(String name) => _$nspReportDirectionEnumValueOf(name);
}

