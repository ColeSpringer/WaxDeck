// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ws_tune_frame.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WsTuneFrame extends WsTuneFrame {
  @override
  final String type;
  @override
  final String? station;

  factory _$WsTuneFrame([void Function(WsTuneFrameBuilder)? updates]) =>
      (WsTuneFrameBuilder()..update(updates))._build();

  _$WsTuneFrame._({required this.type, this.station}) : super._();
  @override
  WsTuneFrame rebuild(void Function(WsTuneFrameBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WsTuneFrameBuilder toBuilder() => WsTuneFrameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WsTuneFrame &&
        type == other.type &&
        station == other.station;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, station.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WsTuneFrame')
          ..add('type', type)
          ..add('station', station))
        .toString();
  }
}

class WsTuneFrameBuilder implements Builder<WsTuneFrame, WsTuneFrameBuilder> {
  _$WsTuneFrame? _$v;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  String? _station;
  String? get station => _$this._station;
  set station(String? station) => _$this._station = station;

  WsTuneFrameBuilder() {
    WsTuneFrame._defaults(this);
  }

  WsTuneFrameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _station = $v.station;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WsTuneFrame other) {
    _$v = other as _$WsTuneFrame;
  }

  @override
  void update(void Function(WsTuneFrameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WsTuneFrame build() => _build();

  _$WsTuneFrame _build() {
    final _$result =
        _$v ??
        _$WsTuneFrame._(
          type: BuiltValueNullFieldError.checkNotNull(
            type,
            r'WsTuneFrame',
            'type',
          ),
          station: station,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
