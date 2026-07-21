//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/health_issue.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'health_issue_page.g.dart';

/// One page of items with outstanding issues.
///
/// Properties:
/// * [items] - Items, worst first.
/// * [nextCursor] - Cursor for the next page; omitted on the last.
@BuiltValue()
abstract class HealthIssuePage implements Built<HealthIssuePage, HealthIssuePageBuilder> {
  /// Items, worst first.
  @BuiltValueField(wireName: r'items')
  BuiltList<HealthIssue> get items;

  /// Cursor for the next page; omitted on the last.
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  HealthIssuePage._();

  factory HealthIssuePage([void updates(HealthIssuePageBuilder b)]) = _$HealthIssuePage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HealthIssuePageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<HealthIssuePage> get serializer => _$HealthIssuePageSerializer();
}

class _$HealthIssuePageSerializer implements PrimitiveSerializer<HealthIssuePage> {
  @override
  final Iterable<Type> types = const [HealthIssuePage, _$HealthIssuePage];

  @override
  final String wireName = r'HealthIssuePage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    HealthIssuePage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'items';
    yield serializers.serialize(
      object.items,
      specifiedType: const FullType(BuiltList, [FullType(HealthIssue)]),
    );
    if (object.nextCursor != null) {
      yield r'nextCursor';
      yield serializers.serialize(
        object.nextCursor,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    HealthIssuePage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required HealthIssuePageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(HealthIssue)]),
          ) as BuiltList<HealthIssue>;
          result.items.replace(valueDes);
          break;
        case r'nextCursor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nextCursor = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  HealthIssuePage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HealthIssuePageBuilder();
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

