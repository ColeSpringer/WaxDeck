//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/radio_directory_entry.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'radio_directory_results.g.dart';

/// Station directory matches.
///
/// Properties:
/// * [entries] - Matches, best first.
@BuiltValue()
abstract class RadioDirectoryResults implements Built<RadioDirectoryResults, RadioDirectoryResultsBuilder> {
  /// Matches, best first.
  @BuiltValueField(wireName: r'entries')
  BuiltList<RadioDirectoryEntry> get entries;

  RadioDirectoryResults._();

  factory RadioDirectoryResults([void updates(RadioDirectoryResultsBuilder b)]) = _$RadioDirectoryResults;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RadioDirectoryResultsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RadioDirectoryResults> get serializer => _$RadioDirectoryResultsSerializer();
}

class _$RadioDirectoryResultsSerializer implements PrimitiveSerializer<RadioDirectoryResults> {
  @override
  final Iterable<Type> types = const [RadioDirectoryResults, _$RadioDirectoryResults];

  @override
  final String wireName = r'RadioDirectoryResults';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RadioDirectoryResults object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entries';
    yield serializers.serialize(
      object.entries,
      specifiedType: const FullType(BuiltList, [FullType(RadioDirectoryEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RadioDirectoryResults object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RadioDirectoryResultsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RadioDirectoryEntry)]),
          ) as BuiltList<RadioDirectoryEntry>;
          result.entries.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RadioDirectoryResults deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RadioDirectoryResultsBuilder();
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

