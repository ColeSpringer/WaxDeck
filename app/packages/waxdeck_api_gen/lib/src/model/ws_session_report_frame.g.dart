// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ws_session_report_frame.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WsSessionReportFrame extends WsSessionReportFrame {
  @override
  final String type;
  @override
  final bool playing;
  @override
  final int positionMs;
  @override
  final int index;
  @override
  final double? rate;
  @override
  final double? volume;
  @override
  final BuiltList<String>? itemPids;
  @override
  final int? queueVersion;
  @override
  final String? repeat;
  @override
  final bool? shuffle;

  factory _$WsSessionReportFrame([
    void Function(WsSessionReportFrameBuilder)? updates,
  ]) => (WsSessionReportFrameBuilder()..update(updates))._build();

  _$WsSessionReportFrame._({
    required this.type,
    required this.playing,
    required this.positionMs,
    required this.index,
    this.rate,
    this.volume,
    this.itemPids,
    this.queueVersion,
    this.repeat,
    this.shuffle,
  }) : super._();
  @override
  WsSessionReportFrame rebuild(
    void Function(WsSessionReportFrameBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  WsSessionReportFrameBuilder toBuilder() =>
      WsSessionReportFrameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WsSessionReportFrame &&
        type == other.type &&
        playing == other.playing &&
        positionMs == other.positionMs &&
        index == other.index &&
        rate == other.rate &&
        volume == other.volume &&
        itemPids == other.itemPids &&
        queueVersion == other.queueVersion &&
        repeat == other.repeat &&
        shuffle == other.shuffle;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, playing.hashCode);
    _$hash = $jc(_$hash, positionMs.hashCode);
    _$hash = $jc(_$hash, index.hashCode);
    _$hash = $jc(_$hash, rate.hashCode);
    _$hash = $jc(_$hash, volume.hashCode);
    _$hash = $jc(_$hash, itemPids.hashCode);
    _$hash = $jc(_$hash, queueVersion.hashCode);
    _$hash = $jc(_$hash, repeat.hashCode);
    _$hash = $jc(_$hash, shuffle.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WsSessionReportFrame')
          ..add('type', type)
          ..add('playing', playing)
          ..add('positionMs', positionMs)
          ..add('index', index)
          ..add('rate', rate)
          ..add('volume', volume)
          ..add('itemPids', itemPids)
          ..add('queueVersion', queueVersion)
          ..add('repeat', repeat)
          ..add('shuffle', shuffle))
        .toString();
  }
}

class WsSessionReportFrameBuilder
    implements Builder<WsSessionReportFrame, WsSessionReportFrameBuilder> {
  _$WsSessionReportFrame? _$v;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  bool? _playing;
  bool? get playing => _$this._playing;
  set playing(bool? playing) => _$this._playing = playing;

  int? _positionMs;
  int? get positionMs => _$this._positionMs;
  set positionMs(int? positionMs) => _$this._positionMs = positionMs;

  int? _index;
  int? get index => _$this._index;
  set index(int? index) => _$this._index = index;

  double? _rate;
  double? get rate => _$this._rate;
  set rate(double? rate) => _$this._rate = rate;

  double? _volume;
  double? get volume => _$this._volume;
  set volume(double? volume) => _$this._volume = volume;

  ListBuilder<String>? _itemPids;
  ListBuilder<String> get itemPids =>
      _$this._itemPids ??= ListBuilder<String>();
  set itemPids(ListBuilder<String>? itemPids) => _$this._itemPids = itemPids;

  int? _queueVersion;
  int? get queueVersion => _$this._queueVersion;
  set queueVersion(int? queueVersion) => _$this._queueVersion = queueVersion;

  String? _repeat;
  String? get repeat => _$this._repeat;
  set repeat(String? repeat) => _$this._repeat = repeat;

  bool? _shuffle;
  bool? get shuffle => _$this._shuffle;
  set shuffle(bool? shuffle) => _$this._shuffle = shuffle;

  WsSessionReportFrameBuilder() {
    WsSessionReportFrame._defaults(this);
  }

  WsSessionReportFrameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _playing = $v.playing;
      _positionMs = $v.positionMs;
      _index = $v.index;
      _rate = $v.rate;
      _volume = $v.volume;
      _itemPids = $v.itemPids?.toBuilder();
      _queueVersion = $v.queueVersion;
      _repeat = $v.repeat;
      _shuffle = $v.shuffle;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WsSessionReportFrame other) {
    _$v = other as _$WsSessionReportFrame;
  }

  @override
  void update(void Function(WsSessionReportFrameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WsSessionReportFrame build() => _build();

  _$WsSessionReportFrame _build() {
    _$WsSessionReportFrame _$result;
    try {
      _$result =
          _$v ??
          _$WsSessionReportFrame._(
            type: BuiltValueNullFieldError.checkNotNull(
              type,
              r'WsSessionReportFrame',
              'type',
            ),
            playing: BuiltValueNullFieldError.checkNotNull(
              playing,
              r'WsSessionReportFrame',
              'playing',
            ),
            positionMs: BuiltValueNullFieldError.checkNotNull(
              positionMs,
              r'WsSessionReportFrame',
              'positionMs',
            ),
            index: BuiltValueNullFieldError.checkNotNull(
              index,
              r'WsSessionReportFrame',
              'index',
            ),
            rate: rate,
            volume: volume,
            itemPids: _itemPids?.build(),
            queueVersion: queueVersion,
            repeat: repeat,
            shuffle: shuffle,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'itemPids';
        _itemPids?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'WsSessionReportFrame',
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
