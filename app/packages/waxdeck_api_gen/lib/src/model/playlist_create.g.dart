// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_create.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaylistCreate extends PlaylistCreate {
  @override
  final String name;
  @override
  final String kind;
  @override
  final String? visibility;
  @override
  final SmartRule? rule;
  @override
  final BuiltList<String>? itemPids;

  factory _$PlaylistCreate([void Function(PlaylistCreateBuilder)? updates]) =>
      (PlaylistCreateBuilder()..update(updates))._build();

  _$PlaylistCreate._({
    required this.name,
    required this.kind,
    this.visibility,
    this.rule,
    this.itemPids,
  }) : super._();
  @override
  PlaylistCreate rebuild(void Function(PlaylistCreateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlaylistCreateBuilder toBuilder() => PlaylistCreateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaylistCreate &&
        name == other.name &&
        kind == other.kind &&
        visibility == other.visibility &&
        rule == other.rule &&
        itemPids == other.itemPids;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, visibility.hashCode);
    _$hash = $jc(_$hash, rule.hashCode);
    _$hash = $jc(_$hash, itemPids.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaylistCreate')
          ..add('name', name)
          ..add('kind', kind)
          ..add('visibility', visibility)
          ..add('rule', rule)
          ..add('itemPids', itemPids))
        .toString();
  }
}

class PlaylistCreateBuilder
    implements Builder<PlaylistCreate, PlaylistCreateBuilder> {
  _$PlaylistCreate? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _kind;
  String? get kind => _$this._kind;
  set kind(String? kind) => _$this._kind = kind;

  String? _visibility;
  String? get visibility => _$this._visibility;
  set visibility(String? visibility) => _$this._visibility = visibility;

  SmartRuleBuilder? _rule;
  SmartRuleBuilder get rule => _$this._rule ??= SmartRuleBuilder();
  set rule(SmartRuleBuilder? rule) => _$this._rule = rule;

  ListBuilder<String>? _itemPids;
  ListBuilder<String> get itemPids =>
      _$this._itemPids ??= ListBuilder<String>();
  set itemPids(ListBuilder<String>? itemPids) => _$this._itemPids = itemPids;

  PlaylistCreateBuilder() {
    PlaylistCreate._defaults(this);
  }

  PlaylistCreateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _kind = $v.kind;
      _visibility = $v.visibility;
      _rule = $v.rule?.toBuilder();
      _itemPids = $v.itemPids?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaylistCreate other) {
    _$v = other as _$PlaylistCreate;
  }

  @override
  void update(void Function(PlaylistCreateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaylistCreate build() => _build();

  _$PlaylistCreate _build() {
    _$PlaylistCreate _$result;
    try {
      _$result =
          _$v ??
          _$PlaylistCreate._(
            name: BuiltValueNullFieldError.checkNotNull(
              name,
              r'PlaylistCreate',
              'name',
            ),
            kind: BuiltValueNullFieldError.checkNotNull(
              kind,
              r'PlaylistCreate',
              'kind',
            ),
            visibility: visibility,
            rule: _rule?.build(),
            itemPids: _itemPids?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'rule';
        _rule?.build();
        _$failedField = 'itemPids';
        _itemPids?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlaylistCreate',
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
