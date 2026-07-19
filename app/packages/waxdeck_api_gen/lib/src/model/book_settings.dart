//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'book_settings.g.dart';

/// The calling user's per-book playback settings. All fields are optional; an absent field means the server default. `PUT` replaces the whole object. 
///
/// Properties:
/// * [speed] - Playback speed memory for this book.
/// * [voiceBoost] - Apply spoken-word loudness normalization for this book.
/// * [trimSilence] - Trim mapped silence spans when playing this book.
@BuiltValue()
abstract class BookSettings implements Built<BookSettings, BookSettingsBuilder> {
  /// Playback speed memory for this book.
  @BuiltValueField(wireName: r'speed')
  double? get speed;

  /// Apply spoken-word loudness normalization for this book.
  @BuiltValueField(wireName: r'voiceBoost')
  bool? get voiceBoost;

  /// Trim mapped silence spans when playing this book.
  @BuiltValueField(wireName: r'trimSilence')
  bool? get trimSilence;

  BookSettings._();

  factory BookSettings([void updates(BookSettingsBuilder b)]) = _$BookSettings;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookSettingsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookSettings> get serializer => _$BookSettingsSerializer();
}

class _$BookSettingsSerializer implements PrimitiveSerializer<BookSettings> {
  @override
  final Iterable<Type> types = const [BookSettings, _$BookSettings];

  @override
  final String wireName = r'BookSettings';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookSettings object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.speed != null) {
      yield r'speed';
      yield serializers.serialize(
        object.speed,
        specifiedType: const FullType(double),
      );
    }
    if (object.voiceBoost != null) {
      yield r'voiceBoost';
      yield serializers.serialize(
        object.voiceBoost,
        specifiedType: const FullType(bool),
      );
    }
    if (object.trimSilence != null) {
      yield r'trimSilence';
      yield serializers.serialize(
        object.trimSilence,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BookSettings object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BookSettingsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'speed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.speed = valueDes;
          break;
        case r'voiceBoost':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.voiceBoost = valueDes;
          break;
        case r'trimSilence':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.trimSilence = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookSettings deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookSettingsBuilder();
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

