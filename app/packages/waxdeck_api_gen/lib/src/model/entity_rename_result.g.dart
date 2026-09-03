// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entity_rename_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const EntityRenameResultOutcomeEnum _$entityRenameResultOutcomeEnum_renamed =
    const EntityRenameResultOutcomeEnum._('renamed');
const EntityRenameResultOutcomeEnum _$entityRenameResultOutcomeEnum_merged =
    const EntityRenameResultOutcomeEnum._('merged');
const EntityRenameResultOutcomeEnum _$entityRenameResultOutcomeEnum_refreshed =
    const EntityRenameResultOutcomeEnum._('refreshed');
const EntityRenameResultOutcomeEnum
_$entityRenameResultOutcomeEnum_unknownDefaultOpenApi =
    const EntityRenameResultOutcomeEnum._('unknownDefaultOpenApi');

EntityRenameResultOutcomeEnum _$entityRenameResultOutcomeEnumValueOf(
  String name,
) {
  switch (name) {
    case 'renamed':
      return _$entityRenameResultOutcomeEnum_renamed;
    case 'merged':
      return _$entityRenameResultOutcomeEnum_merged;
    case 'refreshed':
      return _$entityRenameResultOutcomeEnum_refreshed;
    case 'unknownDefaultOpenApi':
      return _$entityRenameResultOutcomeEnum_unknownDefaultOpenApi;
    default:
      return _$entityRenameResultOutcomeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<EntityRenameResultOutcomeEnum>
_$entityRenameResultOutcomeEnumValues = BuiltSet<EntityRenameResultOutcomeEnum>(
  const <EntityRenameResultOutcomeEnum>[
    _$entityRenameResultOutcomeEnum_renamed,
    _$entityRenameResultOutcomeEnum_merged,
    _$entityRenameResultOutcomeEnum_refreshed,
    _$entityRenameResultOutcomeEnum_unknownDefaultOpenApi,
  ],
);

Serializer<EntityRenameResultOutcomeEnum>
_$entityRenameResultOutcomeEnumSerializer =
    _$EntityRenameResultOutcomeEnumSerializer();

class _$EntityRenameResultOutcomeEnumSerializer
    implements PrimitiveSerializer<EntityRenameResultOutcomeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'renamed': 'renamed',
    'merged': 'merged',
    'refreshed': 'refreshed',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'renamed': 'renamed',
    'merged': 'merged',
    'refreshed': 'refreshed',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[EntityRenameResultOutcomeEnum];
  @override
  final String wireName = 'EntityRenameResultOutcomeEnum';

  @override
  Object serialize(
    Serializers serializers,
    EntityRenameResultOutcomeEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  EntityRenameResultOutcomeEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => EntityRenameResultOutcomeEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$EntityRenameResult extends EntityRenameResult {
  @override
  final String entityPid;
  @override
  final EntityRenameResultOutcomeEnum outcome;
  @override
  final String? mergedInto;
  @override
  final BuiltList<String>? movedAlbums;
  @override
  final int members;
  @override
  final int credits;
  @override
  final BuiltList<WriteBackFailure>? failures;

  factory _$EntityRenameResult([
    void Function(EntityRenameResultBuilder)? updates,
  ]) => (EntityRenameResultBuilder()..update(updates))._build();

  _$EntityRenameResult._({
    required this.entityPid,
    required this.outcome,
    this.mergedInto,
    this.movedAlbums,
    required this.members,
    required this.credits,
    this.failures,
  }) : super._();
  @override
  EntityRenameResult rebuild(
    void Function(EntityRenameResultBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  EntityRenameResultBuilder toBuilder() =>
      EntityRenameResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EntityRenameResult &&
        entityPid == other.entityPid &&
        outcome == other.outcome &&
        mergedInto == other.mergedInto &&
        movedAlbums == other.movedAlbums &&
        members == other.members &&
        credits == other.credits &&
        failures == other.failures;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entityPid.hashCode);
    _$hash = $jc(_$hash, outcome.hashCode);
    _$hash = $jc(_$hash, mergedInto.hashCode);
    _$hash = $jc(_$hash, movedAlbums.hashCode);
    _$hash = $jc(_$hash, members.hashCode);
    _$hash = $jc(_$hash, credits.hashCode);
    _$hash = $jc(_$hash, failures.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EntityRenameResult')
          ..add('entityPid', entityPid)
          ..add('outcome', outcome)
          ..add('mergedInto', mergedInto)
          ..add('movedAlbums', movedAlbums)
          ..add('members', members)
          ..add('credits', credits)
          ..add('failures', failures))
        .toString();
  }
}

class EntityRenameResultBuilder
    implements Builder<EntityRenameResult, EntityRenameResultBuilder> {
  _$EntityRenameResult? _$v;

  String? _entityPid;
  String? get entityPid => _$this._entityPid;
  set entityPid(String? entityPid) => _$this._entityPid = entityPid;

  EntityRenameResultOutcomeEnum? _outcome;
  EntityRenameResultOutcomeEnum? get outcome => _$this._outcome;
  set outcome(EntityRenameResultOutcomeEnum? outcome) =>
      _$this._outcome = outcome;

  String? _mergedInto;
  String? get mergedInto => _$this._mergedInto;
  set mergedInto(String? mergedInto) => _$this._mergedInto = mergedInto;

  ListBuilder<String>? _movedAlbums;
  ListBuilder<String> get movedAlbums =>
      _$this._movedAlbums ??= ListBuilder<String>();
  set movedAlbums(ListBuilder<String>? movedAlbums) =>
      _$this._movedAlbums = movedAlbums;

  int? _members;
  int? get members => _$this._members;
  set members(int? members) => _$this._members = members;

  int? _credits;
  int? get credits => _$this._credits;
  set credits(int? credits) => _$this._credits = credits;

  ListBuilder<WriteBackFailure>? _failures;
  ListBuilder<WriteBackFailure> get failures =>
      _$this._failures ??= ListBuilder<WriteBackFailure>();
  set failures(ListBuilder<WriteBackFailure>? failures) =>
      _$this._failures = failures;

  EntityRenameResultBuilder() {
    EntityRenameResult._defaults(this);
  }

  EntityRenameResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entityPid = $v.entityPid;
      _outcome = $v.outcome;
      _mergedInto = $v.mergedInto;
      _movedAlbums = $v.movedAlbums?.toBuilder();
      _members = $v.members;
      _credits = $v.credits;
      _failures = $v.failures?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EntityRenameResult other) {
    _$v = other as _$EntityRenameResult;
  }

  @override
  void update(void Function(EntityRenameResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EntityRenameResult build() => _build();

  _$EntityRenameResult _build() {
    _$EntityRenameResult _$result;
    try {
      _$result =
          _$v ??
          _$EntityRenameResult._(
            entityPid: BuiltValueNullFieldError.checkNotNull(
              entityPid,
              r'EntityRenameResult',
              'entityPid',
            ),
            outcome: BuiltValueNullFieldError.checkNotNull(
              outcome,
              r'EntityRenameResult',
              'outcome',
            ),
            mergedInto: mergedInto,
            movedAlbums: _movedAlbums?.build(),
            members: BuiltValueNullFieldError.checkNotNull(
              members,
              r'EntityRenameResult',
              'members',
            ),
            credits: BuiltValueNullFieldError.checkNotNull(
              credits,
              r'EntityRenameResult',
              'credits',
            ),
            failures: _failures?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'movedAlbums';
        _movedAlbums?.build();

        _$failedField = 'failures';
        _failures?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EntityRenameResult',
          _$failedField,
          e.toString(),
        );
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
