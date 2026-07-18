//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/rejected_listen.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'listen_ingest_result.g.dart';

/// Outcome of a listen ingest batch.
///
/// Properties:
/// * [accepted] - Sessions recorded for the first time.
/// * [duplicates] - Sessions already recorded (replay of a known `sessionId`); ignored without error.
/// * [rejected] - Sessions that could not be recorded at all (unknown item, malformed fields).
@BuiltValue()
abstract class ListenIngestResult implements Built<ListenIngestResult, ListenIngestResultBuilder> {
  /// Sessions recorded for the first time.
  @BuiltValueField(wireName: r'accepted')
  int get accepted;

  /// Sessions already recorded (replay of a known `sessionId`); ignored without error.
  @BuiltValueField(wireName: r'duplicates')
  int get duplicates;

  /// Sessions that could not be recorded at all (unknown item, malformed fields).
  @BuiltValueField(wireName: r'rejected')
  BuiltList<RejectedListen>? get rejected;

  ListenIngestResult._();

  factory ListenIngestResult([void updates(ListenIngestResultBuilder b)]) = _$ListenIngestResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListenIngestResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListenIngestResult> get serializer => _$ListenIngestResultSerializer();
}

class _$ListenIngestResultSerializer implements PrimitiveSerializer<ListenIngestResult> {
  @override
  final Iterable<Type> types = const [ListenIngestResult, _$ListenIngestResult];

  @override
  final String wireName = r'ListenIngestResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListenIngestResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'accepted';
    yield serializers.serialize(
      object.accepted,
      specifiedType: const FullType(int),
    );
    yield r'duplicates';
    yield serializers.serialize(
      object.duplicates,
      specifiedType: const FullType(int),
    );
    if (object.rejected != null) {
      yield r'rejected';
      yield serializers.serialize(
        object.rejected,
        specifiedType: const FullType(BuiltList, [FullType(RejectedListen)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ListenIngestResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListenIngestResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'accepted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.accepted = valueDes;
          break;
        case r'duplicates':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.duplicates = valueDes;
          break;
        case r'rejected':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RejectedListen)]),
          ) as BuiltList<RejectedListen>;
          result.rejected.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ListenIngestResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListenIngestResultBuilder();
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

