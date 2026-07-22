//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/sealed_casualty.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'restore_plan.g.dart';

/// A staged restore: what will happen at the next server start. 
///
/// Properties:
/// * [backupId] - The backup the restore applies.
/// * [stagedAt] - When the restore was staged.
/// * [keyfilePresent] - Whether this server holds an encryption key.
/// * [keyfileMatches] - Whether this server's key opens the archive's sealed credentials. False means every entry in `sealedCasualties` becomes unusable after restore and is marked pending re-auth instead of surfacing as scattered errors. 
/// * [sealedCasualties] - The credentials that break when the key does not match; empty when it does. 
/// * [warnings] - Human-readable cautions (schema differences, a server-version gap, an archive older than the current data). 
@BuiltValue()
abstract class RestorePlan implements Built<RestorePlan, RestorePlanBuilder> {
  /// The backup the restore applies.
  @BuiltValueField(wireName: r'backupId')
  String get backupId;

  /// When the restore was staged.
  @BuiltValueField(wireName: r'stagedAt')
  DateTime get stagedAt;

  /// Whether this server holds an encryption key.
  @BuiltValueField(wireName: r'keyfilePresent')
  bool get keyfilePresent;

  /// Whether this server's key opens the archive's sealed credentials. False means every entry in `sealedCasualties` becomes unusable after restore and is marked pending re-auth instead of surfacing as scattered errors. 
  @BuiltValueField(wireName: r'keyfileMatches')
  bool get keyfileMatches;

  /// The credentials that break when the key does not match; empty when it does. 
  @BuiltValueField(wireName: r'sealedCasualties')
  BuiltList<SealedCasualty> get sealedCasualties;

  /// Human-readable cautions (schema differences, a server-version gap, an archive older than the current data). 
  @BuiltValueField(wireName: r'warnings')
  BuiltList<String> get warnings;

  RestorePlan._();

  factory RestorePlan([void updates(RestorePlanBuilder b)]) = _$RestorePlan;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RestorePlanBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RestorePlan> get serializer => _$RestorePlanSerializer();
}

class _$RestorePlanSerializer implements PrimitiveSerializer<RestorePlan> {
  @override
  final Iterable<Type> types = const [RestorePlan, _$RestorePlan];

  @override
  final String wireName = r'RestorePlan';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RestorePlan object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'backupId';
    yield serializers.serialize(
      object.backupId,
      specifiedType: const FullType(String),
    );
    yield r'stagedAt';
    yield serializers.serialize(
      object.stagedAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'keyfilePresent';
    yield serializers.serialize(
      object.keyfilePresent,
      specifiedType: const FullType(bool),
    );
    yield r'keyfileMatches';
    yield serializers.serialize(
      object.keyfileMatches,
      specifiedType: const FullType(bool),
    );
    yield r'sealedCasualties';
    yield serializers.serialize(
      object.sealedCasualties,
      specifiedType: const FullType(BuiltList, [FullType(SealedCasualty)]),
    );
    yield r'warnings';
    yield serializers.serialize(
      object.warnings,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RestorePlan object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RestorePlanBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'backupId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.backupId = valueDes;
          break;
        case r'stagedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.stagedAt = valueDes;
          break;
        case r'keyfilePresent':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.keyfilePresent = valueDes;
          break;
        case r'keyfileMatches':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.keyfileMatches = valueDes;
          break;
        case r'sealedCasualties':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(SealedCasualty)]),
          ) as BuiltList<SealedCasualty>;
          result.sealedCasualties.replace(valueDes);
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
  RestorePlan deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RestorePlanBuilder();
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

