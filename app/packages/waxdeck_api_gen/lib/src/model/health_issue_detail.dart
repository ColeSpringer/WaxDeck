//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'health_issue_detail.g.dart';

/// What a failing rule measured, present when one did: `duration-mismatch` carries both lengths of the file that fails it, which for a book may be one part and for a cue-carved track is the whole file it is cut from. 
///
/// Properties:
/// * [headerMs] - The length the file's header states.
/// * [decodedMs] - The length its audio decodes to.
/// * [partIndex] - The multi-file book part the lengths are of, zero-based.
/// * [wholeFile] - The lengths are of the whole file a cue-carved track is cut from.
@BuiltValue()
abstract class HealthIssueDetail implements Built<HealthIssueDetail, HealthIssueDetailBuilder> {
  /// The length the file's header states.
  @BuiltValueField(wireName: r'headerMs')
  int? get headerMs;

  /// The length its audio decodes to.
  @BuiltValueField(wireName: r'decodedMs')
  int? get decodedMs;

  /// The multi-file book part the lengths are of, zero-based.
  @BuiltValueField(wireName: r'partIndex')
  int? get partIndex;

  /// The lengths are of the whole file a cue-carved track is cut from.
  @BuiltValueField(wireName: r'wholeFile')
  bool? get wholeFile;

  HealthIssueDetail._();

  factory HealthIssueDetail([void updates(HealthIssueDetailBuilder b)]) = _$HealthIssueDetail;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HealthIssueDetailBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<HealthIssueDetail> get serializer => _$HealthIssueDetailSerializer();
}

class _$HealthIssueDetailSerializer implements PrimitiveSerializer<HealthIssueDetail> {
  @override
  final Iterable<Type> types = const [HealthIssueDetail, _$HealthIssueDetail];

  @override
  final String wireName = r'HealthIssueDetail';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    HealthIssueDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.headerMs != null) {
      yield r'headerMs';
      yield serializers.serialize(
        object.headerMs,
        specifiedType: const FullType(int),
      );
    }
    if (object.decodedMs != null) {
      yield r'decodedMs';
      yield serializers.serialize(
        object.decodedMs,
        specifiedType: const FullType(int),
      );
    }
    if (object.partIndex != null) {
      yield r'partIndex';
      yield serializers.serialize(
        object.partIndex,
        specifiedType: const FullType(int),
      );
    }
    if (object.wholeFile != null) {
      yield r'wholeFile';
      yield serializers.serialize(
        object.wholeFile,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    HealthIssueDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required HealthIssueDetailBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'headerMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.headerMs = valueDes;
          break;
        case r'decodedMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.decodedMs = valueDes;
          break;
        case r'partIndex':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.partIndex = valueDes;
          break;
        case r'wholeFile':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.wholeFile = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  HealthIssueDetail deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HealthIssueDetailBuilder();
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


