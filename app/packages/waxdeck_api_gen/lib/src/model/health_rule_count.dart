//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'health_rule_count.g.dart';

/// One rule's current standing.
///
/// Properties:
/// * [rule] - The rule name.
/// * [label] - Human-readable rule label.
/// * [failing] - Items currently failing the rule.
/// * [fixable] - Whether the bulk-fix endpoint can fix this rule on this install. 
/// * [fixing] - True while a fix for the rule is under way: a pass-backed fix from its start until its re-check lands, a task-backed one while its task is queued or running. Another fix for the rule answers `conflict` meanwhile. 
/// * [fixBlocked] - Why a rule that has a fix cannot be fixed on this install; absent when `fixable`, and for rules with no fix at all. `needs-contact`: the server has no enrichment contact, which is what lets it ask MusicBrainz and the other free public sources. `needs-lyrics-source`, `needs-art-source`, `needs-genre-source`, `needs-book-source`: no enrichment source the fix could use, for lyrics, artwork, genres, or book metadata, is switched on. `no-managed-library`: no library is managed, so there is no layout for paths to match. 
@BuiltValue()
abstract class HealthRuleCount implements Built<HealthRuleCount, HealthRuleCountBuilder> {
  /// The rule name.
  @BuiltValueField(wireName: r'rule')
  String get rule;

  /// Human-readable rule label.
  @BuiltValueField(wireName: r'label')
  String? get label;

  /// Items currently failing the rule.
  @BuiltValueField(wireName: r'failing')
  int get failing;

  /// Whether the bulk-fix endpoint can fix this rule on this install. 
  @BuiltValueField(wireName: r'fixable')
  bool get fixable;

  /// True while a fix for the rule is under way: a pass-backed fix from its start until its re-check lands, a task-backed one while its task is queued or running. Another fix for the rule answers `conflict` meanwhile. 
  @BuiltValueField(wireName: r'fixing')
  bool get fixing;

  /// Why a rule that has a fix cannot be fixed on this install; absent when `fixable`, and for rules with no fix at all. `needs-contact`: the server has no enrichment contact, which is what lets it ask MusicBrainz and the other free public sources. `needs-lyrics-source`, `needs-art-source`, `needs-genre-source`, `needs-book-source`: no enrichment source the fix could use, for lyrics, artwork, genres, or book metadata, is switched on. `no-managed-library`: no library is managed, so there is no layout for paths to match. 
  @BuiltValueField(wireName: r'fixBlocked')
  HealthRuleCountFixBlockedEnum? get fixBlocked;
  // enum fixBlockedEnum {  needs-contact,  needs-lyrics-source,  needs-art-source,  needs-genre-source,  needs-book-source,  no-managed-library,  };

  HealthRuleCount._();

  factory HealthRuleCount([void updates(HealthRuleCountBuilder b)]) = _$HealthRuleCount;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HealthRuleCountBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<HealthRuleCount> get serializer => _$HealthRuleCountSerializer();
}

class _$HealthRuleCountSerializer implements PrimitiveSerializer<HealthRuleCount> {
  @override
  final Iterable<Type> types = const [HealthRuleCount, _$HealthRuleCount];

  @override
  final String wireName = r'HealthRuleCount';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    HealthRuleCount object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'rule';
    yield serializers.serialize(
      object.rule,
      specifiedType: const FullType(String),
    );
    if (object.label != null) {
      yield r'label';
      yield serializers.serialize(
        object.label,
        specifiedType: const FullType(String),
      );
    }
    yield r'failing';
    yield serializers.serialize(
      object.failing,
      specifiedType: const FullType(int),
    );
    yield r'fixable';
    yield serializers.serialize(
      object.fixable,
      specifiedType: const FullType(bool),
    );
    yield r'fixing';
    yield serializers.serialize(
      object.fixing,
      specifiedType: const FullType(bool),
    );
    if (object.fixBlocked != null) {
      yield r'fixBlocked';
      yield serializers.serialize(
        object.fixBlocked,
        specifiedType: const FullType(HealthRuleCountFixBlockedEnum),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    HealthRuleCount object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required HealthRuleCountBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'rule':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.rule = valueDes;
          break;
        case r'label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.label = valueDes;
          break;
        case r'failing':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.failing = valueDes;
          break;
        case r'fixable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.fixable = valueDes;
          break;
        case r'fixing':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.fixing = valueDes;
          break;
        case r'fixBlocked':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(HealthRuleCountFixBlockedEnum),
          ) as HealthRuleCountFixBlockedEnum?;
          if (valueDes == null) continue;
          result.fixBlocked = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  HealthRuleCount deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HealthRuleCountBuilder();
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


/// Why a rule that has a fix cannot be fixed on this install; absent when `fixable`, and for rules with no fix at all. `needs-contact`: the server has no enrichment contact, which is what lets it ask MusicBrainz and the other free public sources. `needs-lyrics-source`, `needs-art-source`, `needs-genre-source`, `needs-book-source`: no enrichment source the fix could use, for lyrics, artwork, genres, or book metadata, is switched on. `no-managed-library`: no library is managed, so there is no layout for paths to match. 
class HealthRuleCountFixBlockedEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'needs-contact')
  static const HealthRuleCountFixBlockedEnum needsContact = _$healthRuleCountFixBlockedEnum_needsContact;
  @BuiltValueEnumConst(wireName: r'needs-lyrics-source')
  static const HealthRuleCountFixBlockedEnum needsLyricsSource = _$healthRuleCountFixBlockedEnum_needsLyricsSource;
  @BuiltValueEnumConst(wireName: r'needs-art-source')
  static const HealthRuleCountFixBlockedEnum needsArtSource = _$healthRuleCountFixBlockedEnum_needsArtSource;
  @BuiltValueEnumConst(wireName: r'needs-genre-source')
  static const HealthRuleCountFixBlockedEnum needsGenreSource = _$healthRuleCountFixBlockedEnum_needsGenreSource;
  @BuiltValueEnumConst(wireName: r'needs-book-source')
  static const HealthRuleCountFixBlockedEnum needsBookSource = _$healthRuleCountFixBlockedEnum_needsBookSource;
  @BuiltValueEnumConst(wireName: r'no-managed-library')
  static const HealthRuleCountFixBlockedEnum noManagedLibrary = _$healthRuleCountFixBlockedEnum_noManagedLibrary;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const HealthRuleCountFixBlockedEnum unknownDefaultOpenApi = _$healthRuleCountFixBlockedEnum_unknownDefaultOpenApi;

  static Serializer<HealthRuleCountFixBlockedEnum> get serializer => _$healthRuleCountFixBlockedEnumSerializer;

  const HealthRuleCountFixBlockedEnum._(String name): super(name);

  static BuiltSet<HealthRuleCountFixBlockedEnum> get values => _$healthRuleCountFixBlockedEnumValues;
  static HealthRuleCountFixBlockedEnum valueOf(String name) => _$healthRuleCountFixBlockedEnumValueOf(name);
}

