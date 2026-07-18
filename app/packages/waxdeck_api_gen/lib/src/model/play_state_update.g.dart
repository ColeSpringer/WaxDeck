// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'play_state_update.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlayStateUpdate extends PlayStateUpdate {
  @override
  final int positionMs;

  factory _$PlayStateUpdate([void Function(PlayStateUpdateBuilder)? updates]) =>
      (PlayStateUpdateBuilder()..update(updates))._build();

  _$PlayStateUpdate._({required this.positionMs}) : super._();
  @override
  PlayStateUpdate rebuild(void Function(PlayStateUpdateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlayStateUpdateBuilder toBuilder() => PlayStateUpdateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlayStateUpdate && positionMs == other.positionMs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, positionMs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'PlayStateUpdate',
    )..add('positionMs', positionMs)).toString();
  }
}

class PlayStateUpdateBuilder
    implements Builder<PlayStateUpdate, PlayStateUpdateBuilder> {
  _$PlayStateUpdate? _$v;

  int? _positionMs;
  int? get positionMs => _$this._positionMs;
  set positionMs(int? positionMs) => _$this._positionMs = positionMs;

  PlayStateUpdateBuilder() {
    PlayStateUpdate._defaults(this);
  }

  PlayStateUpdateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _positionMs = $v.positionMs;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlayStateUpdate other) {
    _$v = other as _$PlayStateUpdate;
  }

  @override
  void update(void Function(PlayStateUpdateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlayStateUpdate build() => _build();

  _$PlayStateUpdate _build() {
    final _$result =
        _$v ??
        _$PlayStateUpdate._(
          positionMs: BuiltValueNullFieldError.checkNotNull(
            positionMs,
            r'PlayStateUpdate',
            'positionMs',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
