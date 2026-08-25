// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rescan_options.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RescanOptions extends RescanOptions {
  @override
  final bool? force;

  factory _$RescanOptions([void Function(RescanOptionsBuilder)? updates]) =>
      (RescanOptionsBuilder()..update(updates))._build();

  _$RescanOptions._({this.force}) : super._();
  @override
  RescanOptions rebuild(void Function(RescanOptionsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RescanOptionsBuilder toBuilder() => RescanOptionsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RescanOptions && force == other.force;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, force.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'RescanOptions',
    )..add('force', force)).toString();
  }
}

class RescanOptionsBuilder
    implements Builder<RescanOptions, RescanOptionsBuilder> {
  _$RescanOptions? _$v;

  bool? _force;
  bool? get force => _$this._force;
  set force(bool? force) => _$this._force = force;

  RescanOptionsBuilder() {
    RescanOptions._defaults(this);
  }

  RescanOptionsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _force = $v.force;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RescanOptions other) {
    _$v = other as _$RescanOptions;
  }

  @override
  void update(void Function(RescanOptionsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RescanOptions build() => _build();

  _$RescanOptions _build() {
    final _$result = _$v ?? _$RescanOptions._(force: force);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
