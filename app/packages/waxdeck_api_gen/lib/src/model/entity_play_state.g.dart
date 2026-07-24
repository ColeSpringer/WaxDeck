// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entity_play_state.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EntityPlayState extends EntityPlayState {
  @override
  final String pid;
  @override
  final bool starred;
  @override
  final DateTime? starredAt;
  @override
  final int? rating;
  @override
  final DateTime? updatedAt;

  factory _$EntityPlayState([void Function(EntityPlayStateBuilder)? updates]) =>
      (EntityPlayStateBuilder()..update(updates))._build();

  _$EntityPlayState._({
    required this.pid,
    required this.starred,
    this.starredAt,
    this.rating,
    this.updatedAt,
  }) : super._();
  @override
  EntityPlayState rebuild(void Function(EntityPlayStateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EntityPlayStateBuilder toBuilder() => EntityPlayStateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EntityPlayState &&
        pid == other.pid &&
        starred == other.starred &&
        starredAt == other.starredAt &&
        rating == other.rating &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, starred.hashCode);
    _$hash = $jc(_$hash, starredAt.hashCode);
    _$hash = $jc(_$hash, rating.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EntityPlayState')
          ..add('pid', pid)
          ..add('starred', starred)
          ..add('starredAt', starredAt)
          ..add('rating', rating)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class EntityPlayStateBuilder
    implements Builder<EntityPlayState, EntityPlayStateBuilder> {
  _$EntityPlayState? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  bool? _starred;
  bool? get starred => _$this._starred;
  set starred(bool? starred) => _$this._starred = starred;

  DateTime? _starredAt;
  DateTime? get starredAt => _$this._starredAt;
  set starredAt(DateTime? starredAt) => _$this._starredAt = starredAt;

  int? _rating;
  int? get rating => _$this._rating;
  set rating(int? rating) => _$this._rating = rating;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  EntityPlayStateBuilder() {
    EntityPlayState._defaults(this);
  }

  EntityPlayStateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _starred = $v.starred;
      _starredAt = $v.starredAt;
      _rating = $v.rating;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EntityPlayState other) {
    _$v = other as _$EntityPlayState;
  }

  @override
  void update(void Function(EntityPlayStateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EntityPlayState build() => _build();

  _$EntityPlayState _build() {
    final _$result =
        _$v ??
        _$EntityPlayState._(
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'EntityPlayState',
            'pid',
          ),
          starred: BuiltValueNullFieldError.checkNotNull(
            starred,
            r'EntityPlayState',
            'starred',
          ),
          starredAt: starredAt,
          rating: rating,
          updatedAt: updatedAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
