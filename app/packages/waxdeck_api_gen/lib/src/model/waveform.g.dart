// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'waveform.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Waveform extends Waveform {
  @override
  final String state;
  @override
  final BuiltList<int>? peaks;
  @override
  final int? resolution;
  @override
  final String? essenceHash;

  factory _$Waveform([void Function(WaveformBuilder)? updates]) =>
      (WaveformBuilder()..update(updates))._build();

  _$Waveform._({
    required this.state,
    this.peaks,
    this.resolution,
    this.essenceHash,
  }) : super._();
  @override
  Waveform rebuild(void Function(WaveformBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WaveformBuilder toBuilder() => WaveformBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Waveform &&
        state == other.state &&
        peaks == other.peaks &&
        resolution == other.resolution &&
        essenceHash == other.essenceHash;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, state.hashCode);
    _$hash = $jc(_$hash, peaks.hashCode);
    _$hash = $jc(_$hash, resolution.hashCode);
    _$hash = $jc(_$hash, essenceHash.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Waveform')
          ..add('state', state)
          ..add('peaks', peaks)
          ..add('resolution', resolution)
          ..add('essenceHash', essenceHash))
        .toString();
  }
}

class WaveformBuilder implements Builder<Waveform, WaveformBuilder> {
  _$Waveform? _$v;

  String? _state;
  String? get state => _$this._state;
  set state(String? state) => _$this._state = state;

  ListBuilder<int>? _peaks;
  ListBuilder<int> get peaks => _$this._peaks ??= ListBuilder<int>();
  set peaks(ListBuilder<int>? peaks) => _$this._peaks = peaks;

  int? _resolution;
  int? get resolution => _$this._resolution;
  set resolution(int? resolution) => _$this._resolution = resolution;

  String? _essenceHash;
  String? get essenceHash => _$this._essenceHash;
  set essenceHash(String? essenceHash) => _$this._essenceHash = essenceHash;

  WaveformBuilder() {
    Waveform._defaults(this);
  }

  WaveformBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _state = $v.state;
      _peaks = $v.peaks?.toBuilder();
      _resolution = $v.resolution;
      _essenceHash = $v.essenceHash;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Waveform other) {
    _$v = other as _$Waveform;
  }

  @override
  void update(void Function(WaveformBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Waveform build() => _build();

  _$Waveform _build() {
    _$Waveform _$result;
    try {
      _$result =
          _$v ??
          _$Waveform._(
            state: BuiltValueNullFieldError.checkNotNull(
              state,
              r'Waveform',
              'state',
            ),
            peaks: _peaks?.build(),
            resolution: resolution,
            essenceHash: essenceHash,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'peaks';
        _peaks?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'Waveform',
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
