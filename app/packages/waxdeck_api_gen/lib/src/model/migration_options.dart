//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'migration_options.g.dart';

/// What to import. Everything defaults to true.
///
/// Properties:
/// * [stars] - Starred songs, albums, and artists.
/// * [ratings] - Song and album ratings.
/// * [history] - Play counts, as backdated import-source listen sessions with deterministic ids (re-runs never double-count). 
/// * [progress] - In-progress positions (Subsonic bookmarks, Audiobookshelf media progress) onto matched items' resume state. 
@BuiltValue()
abstract class MigrationOptions implements Built<MigrationOptions, MigrationOptionsBuilder> {
  /// Starred songs, albums, and artists.
  @BuiltValueField(wireName: r'stars')
  bool? get stars;

  /// Song and album ratings.
  @BuiltValueField(wireName: r'ratings')
  bool? get ratings;

  /// Play counts, as backdated import-source listen sessions with deterministic ids (re-runs never double-count). 
  @BuiltValueField(wireName: r'history')
  bool? get history;

  /// In-progress positions (Subsonic bookmarks, Audiobookshelf media progress) onto matched items' resume state. 
  @BuiltValueField(wireName: r'progress')
  bool? get progress;

  MigrationOptions._();

  factory MigrationOptions([void updates(MigrationOptionsBuilder b)]) = _$MigrationOptions;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MigrationOptionsBuilder b) => b
      ..stars = true
      ..ratings = true
      ..history = true
      ..progress = true;

  @BuiltValueSerializer(custom: true)
  static Serializer<MigrationOptions> get serializer => _$MigrationOptionsSerializer();
}

class _$MigrationOptionsSerializer implements PrimitiveSerializer<MigrationOptions> {
  @override
  final Iterable<Type> types = const [MigrationOptions, _$MigrationOptions];

  @override
  final String wireName = r'MigrationOptions';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MigrationOptions object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.stars != null) {
      yield r'stars';
      yield serializers.serialize(
        object.stars,
        specifiedType: const FullType(bool),
      );
    }
    if (object.ratings != null) {
      yield r'ratings';
      yield serializers.serialize(
        object.ratings,
        specifiedType: const FullType(bool),
      );
    }
    if (object.history != null) {
      yield r'history';
      yield serializers.serialize(
        object.history,
        specifiedType: const FullType(bool),
      );
    }
    if (object.progress != null) {
      yield r'progress';
      yield serializers.serialize(
        object.progress,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    MigrationOptions object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MigrationOptionsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'stars':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.stars = valueDes;
          break;
        case r'ratings':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.ratings = valueDes;
          break;
        case r'history':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.history = valueDes;
          break;
        case r'progress':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.progress = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MigrationOptions deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MigrationOptionsBuilder();
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

