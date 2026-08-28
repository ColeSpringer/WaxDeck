//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'commit_credits.g.dart';

/// Replacement people for one credit role inside a compound commit. The write switches live on the commit rather than here. 
///
/// Properties:
/// * [role] - The role, from the kind's role vocabulary.
/// * [names] - The people; empty clears the role.
@BuiltValue()
abstract class CommitCredits implements Built<CommitCredits, CommitCreditsBuilder> {
  /// The role, from the kind's role vocabulary.
  @BuiltValueField(wireName: r'role')
  String get role;

  /// The people; empty clears the role.
  @BuiltValueField(wireName: r'names')
  BuiltList<String> get names;

  CommitCredits._();

  factory CommitCredits([void updates(CommitCreditsBuilder b)]) = _$CommitCredits;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CommitCreditsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CommitCredits> get serializer => _$CommitCreditsSerializer();
}

class _$CommitCreditsSerializer implements PrimitiveSerializer<CommitCredits> {
  @override
  final Iterable<Type> types = const [CommitCredits, _$CommitCredits];

  @override
  final String wireName = r'CommitCredits';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CommitCredits object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'role';
    yield serializers.serialize(
      object.role,
      specifiedType: const FullType(String),
    );
    yield r'names';
    yield serializers.serialize(
      object.names,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CommitCredits object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CommitCreditsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.role = valueDes;
          break;
        case r'names':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.names.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CommitCredits deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CommitCreditsBuilder();
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

