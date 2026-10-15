//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'set_item_kind_request.g.dart';

/// The items to change, and what they become.
///
/// Properties:
/// * [pids] - The items, by pid. Tracks named together whose tags name one book become that book. 
/// * [mediaType] - What the items become.
/// * [writeBack] - Also write the kind into the files. A book gets the audiobook media type, which even a scan that re-derives everything reads back as a book; a track has it cleared, so such a scan reads it as music only where nothing else marks it a book (an `.m4b` name, a narrator, the Audiobook genre, a library that holds Books). Without it the catalog's pin alone keeps the choice. A file that cannot be written is listed in the job result's `writeBackFailures` and the change stands. 
@BuiltValue()
abstract class SetItemKindRequest implements Built<SetItemKindRequest, SetItemKindRequestBuilder> {
  /// The items, by pid. Tracks named together whose tags name one book become that book. 
  @BuiltValueField(wireName: r'pids')
  BuiltList<String> get pids;

  /// What the items become.
  @BuiltValueField(wireName: r'mediaType')
  SetItemKindRequestMediaTypeEnum get mediaType;
  // enum mediaTypeEnum {  music,  audiobook,  };

  /// Also write the kind into the files. A book gets the audiobook media type, which even a scan that re-derives everything reads back as a book; a track has it cleared, so such a scan reads it as music only where nothing else marks it a book (an `.m4b` name, a narrator, the Audiobook genre, a library that holds Books). Without it the catalog's pin alone keeps the choice. A file that cannot be written is listed in the job result's `writeBackFailures` and the change stands. 
  @BuiltValueField(wireName: r'writeBack')
  bool? get writeBack;

  SetItemKindRequest._();

  factory SetItemKindRequest([void updates(SetItemKindRequestBuilder b)]) = _$SetItemKindRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SetItemKindRequestBuilder b) => b
      ..writeBack = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<SetItemKindRequest> get serializer => _$SetItemKindRequestSerializer();
}

class _$SetItemKindRequestSerializer implements PrimitiveSerializer<SetItemKindRequest> {
  @override
  final Iterable<Type> types = const [SetItemKindRequest, _$SetItemKindRequest];

  @override
  final String wireName = r'SetItemKindRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SetItemKindRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pids';
    yield serializers.serialize(
      object.pids,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'mediaType';
    yield serializers.serialize(
      object.mediaType,
      specifiedType: const FullType(SetItemKindRequestMediaTypeEnum),
    );
    if (object.writeBack != null) {
      yield r'writeBack';
      yield serializers.serialize(
        object.writeBack,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SetItemKindRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SetItemKindRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.pids.replace(valueDes);
          break;
        case r'mediaType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SetItemKindRequestMediaTypeEnum),
          ) as SetItemKindRequestMediaTypeEnum;
          result.mediaType = valueDes;
          break;
        case r'writeBack':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.writeBack = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SetItemKindRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SetItemKindRequestBuilder();
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


/// What the items become.
class SetItemKindRequestMediaTypeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'music')
  static const SetItemKindRequestMediaTypeEnum music = _$setItemKindRequestMediaTypeEnum_music;
  @BuiltValueEnumConst(wireName: r'audiobook')
  static const SetItemKindRequestMediaTypeEnum audiobook = _$setItemKindRequestMediaTypeEnum_audiobook;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const SetItemKindRequestMediaTypeEnum unknownDefaultOpenApi = _$setItemKindRequestMediaTypeEnum_unknownDefaultOpenApi;

  static Serializer<SetItemKindRequestMediaTypeEnum> get serializer => _$setItemKindRequestMediaTypeEnumSerializer;

  const SetItemKindRequestMediaTypeEnum._(String name): super(name);

  static BuiltSet<SetItemKindRequestMediaTypeEnum> get values => _$setItemKindRequestMediaTypeEnumValues;
  static SetItemKindRequestMediaTypeEnum valueOf(String name) => _$setItemKindRequestMediaTypeEnumValueOf(name);
}

