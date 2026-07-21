// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lyrics_edit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LyricsEdit extends LyricsEdit {
  @override
  final String? lrc;
  @override
  final String? plain;
  @override
  final bool? writeBack;
  @override
  final bool? lock;
  @override
  final bool? force;

  factory _$LyricsEdit([void Function(LyricsEditBuilder)? updates]) =>
      (LyricsEditBuilder()..update(updates))._build();

  _$LyricsEdit._({this.lrc, this.plain, this.writeBack, this.lock, this.force})
    : super._();
  @override
  LyricsEdit rebuild(void Function(LyricsEditBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LyricsEditBuilder toBuilder() => LyricsEditBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LyricsEdit &&
        lrc == other.lrc &&
        plain == other.plain &&
        writeBack == other.writeBack &&
        lock == other.lock &&
        force == other.force;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, lrc.hashCode);
    _$hash = $jc(_$hash, plain.hashCode);
    _$hash = $jc(_$hash, writeBack.hashCode);
    _$hash = $jc(_$hash, lock.hashCode);
    _$hash = $jc(_$hash, force.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LyricsEdit')
          ..add('lrc', lrc)
          ..add('plain', plain)
          ..add('writeBack', writeBack)
          ..add('lock', lock)
          ..add('force', force))
        .toString();
  }
}

class LyricsEditBuilder implements Builder<LyricsEdit, LyricsEditBuilder> {
  _$LyricsEdit? _$v;

  String? _lrc;
  String? get lrc => _$this._lrc;
  set lrc(String? lrc) => _$this._lrc = lrc;

  String? _plain;
  String? get plain => _$this._plain;
  set plain(String? plain) => _$this._plain = plain;

  bool? _writeBack;
  bool? get writeBack => _$this._writeBack;
  set writeBack(bool? writeBack) => _$this._writeBack = writeBack;

  bool? _lock;
  bool? get lock => _$this._lock;
  set lock(bool? lock) => _$this._lock = lock;

  bool? _force;
  bool? get force => _$this._force;
  set force(bool? force) => _$this._force = force;

  LyricsEditBuilder() {
    LyricsEdit._defaults(this);
  }

  LyricsEditBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _lrc = $v.lrc;
      _plain = $v.plain;
      _writeBack = $v.writeBack;
      _lock = $v.lock;
      _force = $v.force;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LyricsEdit other) {
    _$v = other as _$LyricsEdit;
  }

  @override
  void update(void Function(LyricsEditBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LyricsEdit build() => _build();

  _$LyricsEdit _build() {
    final _$result =
        _$v ??
        _$LyricsEdit._(
          lrc: lrc,
          plain: plain,
          writeBack: writeBack,
          lock: lock,
          force: force,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
