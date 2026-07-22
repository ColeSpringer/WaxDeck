//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/tag_rule.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'permissions.g.dart';

/// Per-account permission toggles. Administrators implicitly hold every permission and no tag rules apply to them. Defaults for a new account: everything below true except `delete`, and no tag rules. 
///
/// Properties:
/// * [download] - May download original files for offline use (the download endpoint and the sync download-info surface). 
/// * [delete] - May delete visible library items to the trash. Permanent deletion always needs the admin role. 
/// * [explicitContent] - May see and play content flagged explicit. False hides RSS-flagged podcast shows and episodes; for music the honest control is a tag deny rule on the advisory tag, because most music has no canonical explicit flag. 
/// * [sharedOutputs] - May control shared device endpoints (cast targets, DLNA renderers, the jukebox output). The caller's own client endpoints are always controllable. 
/// * [managePodcasts] - May subscribe, unsubscribe, add shows, and trigger episode fetches. False leaves existing subscriptions playable but frozen. 
/// * [maxTranscodeKbps] - Per-account transcode bitrate ceiling in kbit/s, overriding the server default. Absent or 0 means the server default applies. 
/// * [tagAllow] - When non-empty, only items matching every rule are visible to the account (kids-mode allow-listing). Applies to music and audiobook items; podcast visibility rides `explicitContent`. 
/// * [tagDeny] - Items matching any rule are hidden from the account. An item without the rule's tag passes a deny rule (absence is not a match), which is the exact deny-list contract. 
@BuiltValue()
abstract class Permissions implements Built<Permissions, PermissionsBuilder> {
  /// May download original files for offline use (the download endpoint and the sync download-info surface). 
  @BuiltValueField(wireName: r'download')
  bool get download;

  /// May delete visible library items to the trash. Permanent deletion always needs the admin role. 
  @BuiltValueField(wireName: r'delete')
  bool get delete;

  /// May see and play content flagged explicit. False hides RSS-flagged podcast shows and episodes; for music the honest control is a tag deny rule on the advisory tag, because most music has no canonical explicit flag. 
  @BuiltValueField(wireName: r'explicitContent')
  bool get explicitContent;

  /// May control shared device endpoints (cast targets, DLNA renderers, the jukebox output). The caller's own client endpoints are always controllable. 
  @BuiltValueField(wireName: r'sharedOutputs')
  bool get sharedOutputs;

  /// May subscribe, unsubscribe, add shows, and trigger episode fetches. False leaves existing subscriptions playable but frozen. 
  @BuiltValueField(wireName: r'managePodcasts')
  bool get managePodcasts;

  /// Per-account transcode bitrate ceiling in kbit/s, overriding the server default. Absent or 0 means the server default applies. 
  @BuiltValueField(wireName: r'maxTranscodeKbps')
  int? get maxTranscodeKbps;

  /// When non-empty, only items matching every rule are visible to the account (kids-mode allow-listing). Applies to music and audiobook items; podcast visibility rides `explicitContent`. 
  @BuiltValueField(wireName: r'tagAllow')
  BuiltList<TagRule>? get tagAllow;

  /// Items matching any rule are hidden from the account. An item without the rule's tag passes a deny rule (absence is not a match), which is the exact deny-list contract. 
  @BuiltValueField(wireName: r'tagDeny')
  BuiltList<TagRule>? get tagDeny;

  Permissions._();

  factory Permissions([void updates(PermissionsBuilder b)]) = _$Permissions;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PermissionsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Permissions> get serializer => _$PermissionsSerializer();
}

class _$PermissionsSerializer implements PrimitiveSerializer<Permissions> {
  @override
  final Iterable<Type> types = const [Permissions, _$Permissions];

  @override
  final String wireName = r'Permissions';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Permissions object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'download';
    yield serializers.serialize(
      object.download,
      specifiedType: const FullType(bool),
    );
    yield r'delete';
    yield serializers.serialize(
      object.delete,
      specifiedType: const FullType(bool),
    );
    yield r'explicitContent';
    yield serializers.serialize(
      object.explicitContent,
      specifiedType: const FullType(bool),
    );
    yield r'sharedOutputs';
    yield serializers.serialize(
      object.sharedOutputs,
      specifiedType: const FullType(bool),
    );
    yield r'managePodcasts';
    yield serializers.serialize(
      object.managePodcasts,
      specifiedType: const FullType(bool),
    );
    if (object.maxTranscodeKbps != null) {
      yield r'maxTranscodeKbps';
      yield serializers.serialize(
        object.maxTranscodeKbps,
        specifiedType: const FullType(int),
      );
    }
    if (object.tagAllow != null) {
      yield r'tagAllow';
      yield serializers.serialize(
        object.tagAllow,
        specifiedType: const FullType(BuiltList, [FullType(TagRule)]),
      );
    }
    if (object.tagDeny != null) {
      yield r'tagDeny';
      yield serializers.serialize(
        object.tagDeny,
        specifiedType: const FullType(BuiltList, [FullType(TagRule)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Permissions object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PermissionsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'download':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.download = valueDes;
          break;
        case r'delete':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.delete = valueDes;
          break;
        case r'explicitContent':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.explicitContent = valueDes;
          break;
        case r'sharedOutputs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.sharedOutputs = valueDes;
          break;
        case r'managePodcasts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.managePodcasts = valueDes;
          break;
        case r'maxTranscodeKbps':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.maxTranscodeKbps = valueDes;
          break;
        case r'tagAllow':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(TagRule)]),
          ) as BuiltList<TagRule>;
          result.tagAllow.replace(valueDes);
          break;
        case r'tagDeny':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(TagRule)]),
          ) as BuiltList<TagRule>;
          result.tagDeny.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Permissions deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PermissionsBuilder();
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

