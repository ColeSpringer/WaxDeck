//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/write_back_failure.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'detach_result.g.dart';

/// Where a detached track came from and where it landed. The catalog write succeeded whenever this shape returns; write-back trouble rides along in `failures`. 
///
/// Properties:
/// * [itemPid] - The detached track.
/// * [oldAlbumPid] - The album it left.
/// * [newAlbumPid] - The album it landed on. Absent when the track's own tags carry no grouping evidence beyond the release id, which leaves it ungrouped exactly as a scan of those tags would. 
/// * [newReleaseGroupPid] - The release group above that album, when there is one.
/// * [failures] - Files whose tags could not be updated.
@BuiltValue()
abstract class DetachResult implements Built<DetachResult, DetachResultBuilder> {
  /// The detached track.
  @BuiltValueField(wireName: r'itemPid')
  String get itemPid;

  /// The album it left.
  @BuiltValueField(wireName: r'oldAlbumPid')
  String get oldAlbumPid;

  /// The album it landed on. Absent when the track's own tags carry no grouping evidence beyond the release id, which leaves it ungrouped exactly as a scan of those tags would. 
  @BuiltValueField(wireName: r'newAlbumPid')
  String? get newAlbumPid;

  /// The release group above that album, when there is one.
  @BuiltValueField(wireName: r'newReleaseGroupPid')
  String? get newReleaseGroupPid;

  /// Files whose tags could not be updated.
  @BuiltValueField(wireName: r'failures')
  BuiltList<WriteBackFailure>? get failures;

  DetachResult._();

  factory DetachResult([void updates(DetachResultBuilder b)]) = _$DetachResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DetachResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DetachResult> get serializer => _$DetachResultSerializer();
}

class _$DetachResultSerializer implements PrimitiveSerializer<DetachResult> {
  @override
  final Iterable<Type> types = const [DetachResult, _$DetachResult];

  @override
  final String wireName = r'DetachResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DetachResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'itemPid';
    yield serializers.serialize(
      object.itemPid,
      specifiedType: const FullType(String),
    );
    yield r'oldAlbumPid';
    yield serializers.serialize(
      object.oldAlbumPid,
      specifiedType: const FullType(String),
    );
    if (object.newAlbumPid != null) {
      yield r'newAlbumPid';
      yield serializers.serialize(
        object.newAlbumPid,
        specifiedType: const FullType(String),
      );
    }
    if (object.newReleaseGroupPid != null) {
      yield r'newReleaseGroupPid';
      yield serializers.serialize(
        object.newReleaseGroupPid,
        specifiedType: const FullType(String),
      );
    }
    if (object.failures != null) {
      yield r'failures';
      yield serializers.serialize(
        object.failures,
        specifiedType: const FullType(BuiltList, [FullType(WriteBackFailure)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DetachResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DetachResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'itemPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.itemPid = valueDes;
          break;
        case r'oldAlbumPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.oldAlbumPid = valueDes;
          break;
        case r'newAlbumPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.newAlbumPid = valueDes;
          break;
        case r'newReleaseGroupPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.newReleaseGroupPid = valueDes;
          break;
        case r'failures':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(WriteBackFailure)]),
          ) as BuiltList<WriteBackFailure>;
          result.failures.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DetachResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DetachResultBuilder();
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

