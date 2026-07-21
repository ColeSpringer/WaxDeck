//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cast_preflight_base.g.dart';

/// One candidate advertise base and its server-side verdict.
///
/// Properties:
/// * [base_] - The base URL a cast device would fetch media from.
/// * [source_] - Where the candidate came from: `configured` (the public base) or `detected` (the auto-detected LAN address). Open string. 
/// * [reachable] - Whether the server could fetch its own health endpoint through this base. 
/// * [notes] - Plain-language observations: scheme and certificate caveats, name-resolution warnings, why a base is likely or unlikely to work from a cast device. 
@BuiltValue()
abstract class CastPreflightBase implements Built<CastPreflightBase, CastPreflightBaseBuilder> {
  /// The base URL a cast device would fetch media from.
  @BuiltValueField(wireName: r'base')
  String get base_;

  /// Where the candidate came from: `configured` (the public base) or `detected` (the auto-detected LAN address). Open string. 
  @BuiltValueField(wireName: r'source')
  String get source_;

  /// Whether the server could fetch its own health endpoint through this base. 
  @BuiltValueField(wireName: r'reachable')
  bool get reachable;

  /// Plain-language observations: scheme and certificate caveats, name-resolution warnings, why a base is likely or unlikely to work from a cast device. 
  @BuiltValueField(wireName: r'notes')
  BuiltList<String> get notes;

  CastPreflightBase._();

  factory CastPreflightBase([void updates(CastPreflightBaseBuilder b)]) = _$CastPreflightBase;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CastPreflightBaseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CastPreflightBase> get serializer => _$CastPreflightBaseSerializer();
}

class _$CastPreflightBaseSerializer implements PrimitiveSerializer<CastPreflightBase> {
  @override
  final Iterable<Type> types = const [CastPreflightBase, _$CastPreflightBase];

  @override
  final String wireName = r'CastPreflightBase';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CastPreflightBase object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'base';
    yield serializers.serialize(
      object.base_,
      specifiedType: const FullType(String),
    );
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(String),
    );
    yield r'reachable';
    yield serializers.serialize(
      object.reachable,
      specifiedType: const FullType(bool),
    );
    yield r'notes';
    yield serializers.serialize(
      object.notes,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CastPreflightBase object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CastPreflightBaseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'base':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.base_ = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.source_ = valueDes;
          break;
        case r'reachable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.reachable = valueDes;
          break;
        case r'notes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
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
  CastPreflightBase deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CastPreflightBaseBuilder();
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

