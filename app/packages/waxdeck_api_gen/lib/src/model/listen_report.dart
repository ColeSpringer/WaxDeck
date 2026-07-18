//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/listen_session.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'listen_report.g.dart';

/// A batch of listen sessions (a flush of an offline queue, or one live session).
///
/// Properties:
/// * [sessions] 
@BuiltValue()
abstract class ListenReport implements Built<ListenReport, ListenReportBuilder> {
  @BuiltValueField(wireName: r'sessions')
  BuiltList<ListenSession> get sessions;

  ListenReport._();

  factory ListenReport([void updates(ListenReportBuilder b)]) = _$ListenReport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListenReportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListenReport> get serializer => _$ListenReportSerializer();
}

class _$ListenReportSerializer implements PrimitiveSerializer<ListenReport> {
  @override
  final Iterable<Type> types = const [ListenReport, _$ListenReport];

  @override
  final String wireName = r'ListenReport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListenReport object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'sessions';
    yield serializers.serialize(
      object.sessions,
      specifiedType: const FullType(BuiltList, [FullType(ListenSession)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ListenReport object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListenReportBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'sessions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ListenSession)]),
          ) as BuiltList<ListenSession>;
          result.sessions.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ListenReport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListenReportBuilder();
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

