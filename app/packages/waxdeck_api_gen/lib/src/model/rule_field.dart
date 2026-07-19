//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rule_field.g.dart';

/// One rule field and what it accepts.
///
/// Properties:
/// * [name] - Field name as used in conditions and sorts.
/// * [kind] - Value kind: `text`, `number`, `date`, `boolean`, or `mediaType`. A string, not a closed enum. Editors render the value input from this. 
/// * [ops] - Operators this field accepts.
/// * [userState] - True when the field reads the evaluating user's playback state rather than shared catalog data. 
/// * [sortable] - True when the field may appear in `sorts`.
/// * [description] - Short human-readable meaning, for editor tooltips.
@BuiltValue()
abstract class RuleField implements Built<RuleField, RuleFieldBuilder> {
  /// Field name as used in conditions and sorts.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Value kind: `text`, `number`, `date`, `boolean`, or `mediaType`. A string, not a closed enum. Editors render the value input from this. 
  @BuiltValueField(wireName: r'kind')
  String get kind;

  /// Operators this field accepts.
  @BuiltValueField(wireName: r'ops')
  BuiltList<String> get ops;

  /// True when the field reads the evaluating user's playback state rather than shared catalog data. 
  @BuiltValueField(wireName: r'userState')
  bool get userState;

  /// True when the field may appear in `sorts`.
  @BuiltValueField(wireName: r'sortable')
  bool get sortable;

  /// Short human-readable meaning, for editor tooltips.
  @BuiltValueField(wireName: r'description')
  String? get description;

  RuleField._();

  factory RuleField([void updates(RuleFieldBuilder b)]) = _$RuleField;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RuleFieldBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RuleField> get serializer => _$RuleFieldSerializer();
}

class _$RuleFieldSerializer implements PrimitiveSerializer<RuleField> {
  @override
  final Iterable<Type> types = const [RuleField, _$RuleField];

  @override
  final String wireName = r'RuleField';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RuleField object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(String),
    );
    yield r'ops';
    yield serializers.serialize(
      object.ops,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'userState';
    yield serializers.serialize(
      object.userState,
      specifiedType: const FullType(bool),
    );
    yield r'sortable';
    yield serializers.serialize(
      object.sortable,
      specifiedType: const FullType(bool),
    );
    if (object.description != null) {
      yield r'description';
      yield serializers.serialize(
        object.description,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RuleField object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RuleFieldBuilder result,
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
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.kind = valueDes;
          break;
        case r'ops':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.ops.replace(valueDes);
          break;
        case r'userState':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.userState = valueDes;
          break;
        case r'sortable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.sortable = valueDes;
          break;
        case r'description':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.description = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RuleField deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RuleFieldBuilder();
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

