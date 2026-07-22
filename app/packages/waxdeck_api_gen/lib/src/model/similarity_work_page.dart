//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/similarity_work_item.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'similarity_work_page.g.dart';

/// A leased batch of analysis work.
///
/// Properties:
/// * [items] 
/// * [retryAfterSeconds] - How long an idle worker should sleep before polling again. Meaningful when `items` is empty. 
@BuiltValue()
abstract class SimilarityWorkPage implements Built<SimilarityWorkPage, SimilarityWorkPageBuilder> {
  @BuiltValueField(wireName: r'items')
  BuiltList<SimilarityWorkItem> get items;

  /// How long an idle worker should sleep before polling again. Meaningful when `items` is empty. 
  @BuiltValueField(wireName: r'retryAfterSeconds')
  int get retryAfterSeconds;

  SimilarityWorkPage._();

  factory SimilarityWorkPage([void updates(SimilarityWorkPageBuilder b)]) = _$SimilarityWorkPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SimilarityWorkPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SimilarityWorkPage> get serializer => _$SimilarityWorkPageSerializer();
}

class _$SimilarityWorkPageSerializer implements PrimitiveSerializer<SimilarityWorkPage> {
  @override
  final Iterable<Type> types = const [SimilarityWorkPage, _$SimilarityWorkPage];

  @override
  final String wireName = r'SimilarityWorkPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SimilarityWorkPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'items';
    yield serializers.serialize(
      object.items,
      specifiedType: const FullType(BuiltList, [FullType(SimilarityWorkItem)]),
    );
    yield r'retryAfterSeconds';
    yield serializers.serialize(
      object.retryAfterSeconds,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SimilarityWorkPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SimilarityWorkPageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(SimilarityWorkItem)]),
          ) as BuiltList<SimilarityWorkItem>;
          result.items.replace(valueDes);
          break;
        case r'retryAfterSeconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.retryAfterSeconds = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SimilarityWorkPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SimilarityWorkPageBuilder();
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

