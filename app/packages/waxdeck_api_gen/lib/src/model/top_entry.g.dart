// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'top_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TopEntry extends TopEntry {
  @override
  final String name;
  @override
  final String? pid;
  @override
  final String? artUrl;
  @override
  final int plays;
  @override
  final int ms;

  factory _$TopEntry([void Function(TopEntryBuilder)? updates]) =>
      (TopEntryBuilder()..update(updates))._build();

  _$TopEntry._({
    required this.name,
    this.pid,
    this.artUrl,
    required this.plays,
    required this.ms,
  }) : super._();
  @override
  TopEntry rebuild(void Function(TopEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TopEntryBuilder toBuilder() => TopEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TopEntry &&
        name == other.name &&
        pid == other.pid &&
        artUrl == other.artUrl &&
        plays == other.plays &&
        ms == other.ms;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, artUrl.hashCode);
    _$hash = $jc(_$hash, plays.hashCode);
    _$hash = $jc(_$hash, ms.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TopEntry')
          ..add('name', name)
          ..add('pid', pid)
          ..add('artUrl', artUrl)
          ..add('plays', plays)
          ..add('ms', ms))
        .toString();
  }
}

class TopEntryBuilder implements Builder<TopEntry, TopEntryBuilder> {
  _$TopEntry? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _artUrl;
  String? get artUrl => _$this._artUrl;
  set artUrl(String? artUrl) => _$this._artUrl = artUrl;

  int? _plays;
  int? get plays => _$this._plays;
  set plays(int? plays) => _$this._plays = plays;

  int? _ms;
  int? get ms => _$this._ms;
  set ms(int? ms) => _$this._ms = ms;

  TopEntryBuilder() {
    TopEntry._defaults(this);
  }

  TopEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _pid = $v.pid;
      _artUrl = $v.artUrl;
      _plays = $v.plays;
      _ms = $v.ms;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TopEntry other) {
    _$v = other as _$TopEntry;
  }

  @override
  void update(void Function(TopEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TopEntry build() => _build();

  _$TopEntry _build() {
    final _$result =
        _$v ??
        _$TopEntry._(
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'TopEntry',
            'name',
          ),
          pid: pid,
          artUrl: artUrl,
          plays: BuiltValueNullFieldError.checkNotNull(
            plays,
            r'TopEntry',
            'plays',
          ),
          ms: BuiltValueNullFieldError.checkNotNull(ms, r'TopEntry', 'ms'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
