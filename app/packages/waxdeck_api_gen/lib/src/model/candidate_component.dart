//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'candidate_component.g.dart';

/// One named contribution to a candidate's distance, so the queue explains a score instead of asserting it. 
///
/// Properties:
/// * [name] - The field or penalty: `artist`, `album`, `year`, `tracks`, `missing`, `extra`. A string, not a closed enum. 
/// * [distance] - Component distance in 0 to 1 (0 is identical).
/// * [weight] - The component's share of the total.
@BuiltValue()
abstract class CandidateComponent implements Built<CandidateComponent, CandidateComponentBuilder> {
  /// The field or penalty: `artist`, `album`, `year`, `tracks`, `missing`, `extra`. A string, not a closed enum. 
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Component distance in 0 to 1 (0 is identical).
  @BuiltValueField(wireName: r'distance')
  double get distance;

  /// The component's share of the total.
  @BuiltValueField(wireName: r'weight')
  double get weight;

  CandidateComponent._();

  factory CandidateComponent([void updates(CandidateComponentBuilder b)]) = _$CandidateComponent;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CandidateComponentBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CandidateComponent> get serializer => _$CandidateComponentSerializer();
}

class _$CandidateComponentSerializer implements PrimitiveSerializer<CandidateComponent> {
  @override
  final Iterable<Type> types = const [CandidateComponent, _$CandidateComponent];

  @override
  final String wireName = r'CandidateComponent';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CandidateComponent object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'distance';
    yield serializers.serialize(
      object.distance,
      specifiedType: const FullType(double),
    );
    yield r'weight';
    yield serializers.serialize(
      object.weight,
      specifiedType: const FullType(double),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CandidateComponent object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CandidateComponentBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'distance':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.distance = valueDes;
          break;
        case r'weight':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.weight = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CandidateComponent deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CandidateComponentBuilder();
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

