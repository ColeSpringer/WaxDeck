// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Playlist extends Playlist {
  @override
  final String pid;
  @override
  final String? previousPid;
  @override
  final String name;
  @override
  final String kind;
  @override
  final String visibility;
  @override
  final String ownerName;
  @override
  final bool isOwner;
  @override
  final int? itemCount;
  @override
  final SmartRule? rule;
  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;

  factory _$Playlist([void Function(PlaylistBuilder)? updates]) =>
      (PlaylistBuilder()..update(updates))._build();

  _$Playlist._({
    required this.pid,
    this.previousPid,
    required this.name,
    required this.kind,
    required this.visibility,
    required this.ownerName,
    required this.isOwner,
    this.itemCount,
    this.rule,
    required this.createdAt,
    required this.updatedAt,
  }) : super._();
  @override
  Playlist rebuild(void Function(PlaylistBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlaylistBuilder toBuilder() => PlaylistBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Playlist &&
        pid == other.pid &&
        previousPid == other.previousPid &&
        name == other.name &&
        kind == other.kind &&
        visibility == other.visibility &&
        ownerName == other.ownerName &&
        isOwner == other.isOwner &&
        itemCount == other.itemCount &&
        rule == other.rule &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, previousPid.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, visibility.hashCode);
    _$hash = $jc(_$hash, ownerName.hashCode);
    _$hash = $jc(_$hash, isOwner.hashCode);
    _$hash = $jc(_$hash, itemCount.hashCode);
    _$hash = $jc(_$hash, rule.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Playlist')
          ..add('pid', pid)
          ..add('previousPid', previousPid)
          ..add('name', name)
          ..add('kind', kind)
          ..add('visibility', visibility)
          ..add('ownerName', ownerName)
          ..add('isOwner', isOwner)
          ..add('itemCount', itemCount)
          ..add('rule', rule)
          ..add('createdAt', createdAt)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class PlaylistBuilder implements Builder<Playlist, PlaylistBuilder> {
  _$Playlist? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _previousPid;
  String? get previousPid => _$this._previousPid;
  set previousPid(String? previousPid) => _$this._previousPid = previousPid;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _kind;
  String? get kind => _$this._kind;
  set kind(String? kind) => _$this._kind = kind;

  String? _visibility;
  String? get visibility => _$this._visibility;
  set visibility(String? visibility) => _$this._visibility = visibility;

  String? _ownerName;
  String? get ownerName => _$this._ownerName;
  set ownerName(String? ownerName) => _$this._ownerName = ownerName;

  bool? _isOwner;
  bool? get isOwner => _$this._isOwner;
  set isOwner(bool? isOwner) => _$this._isOwner = isOwner;

  int? _itemCount;
  int? get itemCount => _$this._itemCount;
  set itemCount(int? itemCount) => _$this._itemCount = itemCount;

  SmartRuleBuilder? _rule;
  SmartRuleBuilder get rule => _$this._rule ??= SmartRuleBuilder();
  set rule(SmartRuleBuilder? rule) => _$this._rule = rule;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  PlaylistBuilder() {
    Playlist._defaults(this);
  }

  PlaylistBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _previousPid = $v.previousPid;
      _name = $v.name;
      _kind = $v.kind;
      _visibility = $v.visibility;
      _ownerName = $v.ownerName;
      _isOwner = $v.isOwner;
      _itemCount = $v.itemCount;
      _rule = $v.rule?.toBuilder();
      _createdAt = $v.createdAt;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Playlist other) {
    _$v = other as _$Playlist;
  }

  @override
  void update(void Function(PlaylistBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Playlist build() => _build();

  _$Playlist _build() {
    _$Playlist _$result;
    try {
      _$result =
          _$v ??
          _$Playlist._(
            pid: BuiltValueNullFieldError.checkNotNull(pid, r'Playlist', 'pid'),
            previousPid: previousPid,
            name: BuiltValueNullFieldError.checkNotNull(
              name,
              r'Playlist',
              'name',
            ),
            kind: BuiltValueNullFieldError.checkNotNull(
              kind,
              r'Playlist',
              'kind',
            ),
            visibility: BuiltValueNullFieldError.checkNotNull(
              visibility,
              r'Playlist',
              'visibility',
            ),
            ownerName: BuiltValueNullFieldError.checkNotNull(
              ownerName,
              r'Playlist',
              'ownerName',
            ),
            isOwner: BuiltValueNullFieldError.checkNotNull(
              isOwner,
              r'Playlist',
              'isOwner',
            ),
            itemCount: itemCount,
            rule: _rule?.build(),
            createdAt: BuiltValueNullFieldError.checkNotNull(
              createdAt,
              r'Playlist',
              'createdAt',
            ),
            updatedAt: BuiltValueNullFieldError.checkNotNull(
              updatedAt,
              r'Playlist',
              'updatedAt',
            ),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'rule';
        _rule?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'Playlist',
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
