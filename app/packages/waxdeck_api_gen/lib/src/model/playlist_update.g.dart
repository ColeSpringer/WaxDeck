// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_update.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaylistUpdate extends PlaylistUpdate {
  @override
  final String? name;
  @override
  final String? visibility;
  @override
  final SmartRule? rule;

  factory _$PlaylistUpdate([void Function(PlaylistUpdateBuilder)? updates]) =>
      (PlaylistUpdateBuilder()..update(updates))._build();

  _$PlaylistUpdate._({this.name, this.visibility, this.rule}) : super._();
  @override
  PlaylistUpdate rebuild(void Function(PlaylistUpdateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlaylistUpdateBuilder toBuilder() => PlaylistUpdateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaylistUpdate &&
        name == other.name &&
        visibility == other.visibility &&
        rule == other.rule;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, visibility.hashCode);
    _$hash = $jc(_$hash, rule.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaylistUpdate')
          ..add('name', name)
          ..add('visibility', visibility)
          ..add('rule', rule))
        .toString();
  }
}

class PlaylistUpdateBuilder
    implements Builder<PlaylistUpdate, PlaylistUpdateBuilder> {
  _$PlaylistUpdate? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _visibility;
  String? get visibility => _$this._visibility;
  set visibility(String? visibility) => _$this._visibility = visibility;

  SmartRuleBuilder? _rule;
  SmartRuleBuilder get rule => _$this._rule ??= SmartRuleBuilder();
  set rule(SmartRuleBuilder? rule) => _$this._rule = rule;

  PlaylistUpdateBuilder() {
    PlaylistUpdate._defaults(this);
  }

  PlaylistUpdateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _visibility = $v.visibility;
      _rule = $v.rule?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaylistUpdate other) {
    _$v = other as _$PlaylistUpdate;
  }

  @override
  void update(void Function(PlaylistUpdateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaylistUpdate build() => _build();

  _$PlaylistUpdate _build() {
    _$PlaylistUpdate _$result;
    try {
      _$result =
          _$v ??
          _$PlaylistUpdate._(
            name: name,
            visibility: visibility,
            rule: _rule?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'rule';
        _rule?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlaylistUpdate',
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
