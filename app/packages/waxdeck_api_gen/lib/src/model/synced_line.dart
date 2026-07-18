//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'synced_line.g.dart';

/// One time-synced lyric line.
///
/// Properties:
/// * [timeMs] - Line start in milliseconds.
/// * [text] - Line text.
@BuiltValue()
abstract class SyncedLine implements Built<SyncedLine, SyncedLineBuilder> {
  /// Line start in milliseconds.
  @BuiltValueField(wireName: r'timeMs')
  int get timeMs;

  /// Line text.
  @BuiltValueField(wireName: r'text')
  String get text;

  SyncedLine._();

  factory SyncedLine([void updates(SyncedLineBuilder b)]) = _$SyncedLine;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SyncedLineBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SyncedLine> get serializer => _$SyncedLineSerializer();
}

class _$SyncedLineSerializer implements PrimitiveSerializer<SyncedLine> {
  @override
  final Iterable<Type> types = const [SyncedLine, _$SyncedLine];

  @override
  final String wireName = r'SyncedLine';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SyncedLine object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'timeMs';
    yield serializers.serialize(
      object.timeMs,
      specifiedType: const FullType(int),
    );
    yield r'text';
    yield serializers.serialize(
      object.text,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SyncedLine object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SyncedLineBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'timeMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.timeMs = valueDes;
          break;
        case r'text':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.text = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SyncedLine deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SyncedLineBuilder();
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

