// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'duplicate_group.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DuplicateGroup extends DuplicateGroup {
  @override
  final String entityType;
  @override
  final DuplicateEntity survivor;
  @override
  final BuiltList<DuplicateEntity> losers;
  @override
  final String? detail;

  factory _$DuplicateGroup([void Function(DuplicateGroupBuilder)? updates]) =>
      (DuplicateGroupBuilder()..update(updates))._build();

  _$DuplicateGroup._({
    required this.entityType,
    required this.survivor,
    required this.losers,
    this.detail,
  }) : super._();
  @override
  DuplicateGroup rebuild(void Function(DuplicateGroupBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DuplicateGroupBuilder toBuilder() => DuplicateGroupBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DuplicateGroup &&
        entityType == other.entityType &&
        survivor == other.survivor &&
        losers == other.losers &&
        detail == other.detail;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entityType.hashCode);
    _$hash = $jc(_$hash, survivor.hashCode);
    _$hash = $jc(_$hash, losers.hashCode);
    _$hash = $jc(_$hash, detail.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DuplicateGroup')
          ..add('entityType', entityType)
          ..add('survivor', survivor)
          ..add('losers', losers)
          ..add('detail', detail))
        .toString();
  }
}

class DuplicateGroupBuilder
    implements Builder<DuplicateGroup, DuplicateGroupBuilder> {
  _$DuplicateGroup? _$v;

  String? _entityType;
  String? get entityType => _$this._entityType;
  set entityType(String? entityType) => _$this._entityType = entityType;

  DuplicateEntityBuilder? _survivor;
  DuplicateEntityBuilder get survivor =>
      _$this._survivor ??= DuplicateEntityBuilder();
  set survivor(DuplicateEntityBuilder? survivor) => _$this._survivor = survivor;

  ListBuilder<DuplicateEntity>? _losers;
  ListBuilder<DuplicateEntity> get losers =>
      _$this._losers ??= ListBuilder<DuplicateEntity>();
  set losers(ListBuilder<DuplicateEntity>? losers) => _$this._losers = losers;

  String? _detail;
  String? get detail => _$this._detail;
  set detail(String? detail) => _$this._detail = detail;

  DuplicateGroupBuilder() {
    DuplicateGroup._defaults(this);
  }

  DuplicateGroupBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entityType = $v.entityType;
      _survivor = $v.survivor.toBuilder();
      _losers = $v.losers.toBuilder();
      _detail = $v.detail;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DuplicateGroup other) {
    _$v = other as _$DuplicateGroup;
  }

  @override
  void update(void Function(DuplicateGroupBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DuplicateGroup build() => _build();

  _$DuplicateGroup _build() {
    _$DuplicateGroup _$result;
    try {
      _$result =
          _$v ??
          _$DuplicateGroup._(
            entityType: BuiltValueNullFieldError.checkNotNull(
              entityType,
              r'DuplicateGroup',
              'entityType',
            ),
            survivor: survivor.build(),
            losers: losers.build(),
            detail: detail,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'survivor';
        survivor.build();
        _$failedField = 'losers';
        losers.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'DuplicateGroup',
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
