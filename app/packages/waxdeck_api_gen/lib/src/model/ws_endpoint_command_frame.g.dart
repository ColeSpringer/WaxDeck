// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ws_endpoint_command_frame.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WsEndpointCommandFrame extends WsEndpointCommandFrame {
  @override
  final String type;
  @override
  final String id;
  @override
  final String sessionId;
  @override
  final String verb;
  @override
  final BuiltList<String>? itemPids;
  @override
  final int? index;
  @override
  final int? positionMs;
  @override
  final bool? play;
  @override
  final double? volume;
  @override
  final double? rate;
  @override
  final String? repeat;
  @override
  final bool? shuffle;

  factory _$WsEndpointCommandFrame([
    void Function(WsEndpointCommandFrameBuilder)? updates,
  ]) => (WsEndpointCommandFrameBuilder()..update(updates))._build();

  _$WsEndpointCommandFrame._({
    required this.type,
    required this.id,
    required this.sessionId,
    required this.verb,
    this.itemPids,
    this.index,
    this.positionMs,
    this.play,
    this.volume,
    this.rate,
    this.repeat,
    this.shuffle,
  }) : super._();
  @override
  WsEndpointCommandFrame rebuild(
    void Function(WsEndpointCommandFrameBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  WsEndpointCommandFrameBuilder toBuilder() =>
      WsEndpointCommandFrameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WsEndpointCommandFrame &&
        type == other.type &&
        id == other.id &&
        sessionId == other.sessionId &&
        verb == other.verb &&
        itemPids == other.itemPids &&
        index == other.index &&
        positionMs == other.positionMs &&
        play == other.play &&
        volume == other.volume &&
        rate == other.rate &&
        repeat == other.repeat &&
        shuffle == other.shuffle;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, sessionId.hashCode);
    _$hash = $jc(_$hash, verb.hashCode);
    _$hash = $jc(_$hash, itemPids.hashCode);
    _$hash = $jc(_$hash, index.hashCode);
    _$hash = $jc(_$hash, positionMs.hashCode);
    _$hash = $jc(_$hash, play.hashCode);
    _$hash = $jc(_$hash, volume.hashCode);
    _$hash = $jc(_$hash, rate.hashCode);
    _$hash = $jc(_$hash, repeat.hashCode);
    _$hash = $jc(_$hash, shuffle.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WsEndpointCommandFrame')
          ..add('type', type)
          ..add('id', id)
          ..add('sessionId', sessionId)
          ..add('verb', verb)
          ..add('itemPids', itemPids)
          ..add('index', index)
          ..add('positionMs', positionMs)
          ..add('play', play)
          ..add('volume', volume)
          ..add('rate', rate)
          ..add('repeat', repeat)
          ..add('shuffle', shuffle))
        .toString();
  }
}

class WsEndpointCommandFrameBuilder
    implements Builder<WsEndpointCommandFrame, WsEndpointCommandFrameBuilder> {
  _$WsEndpointCommandFrame? _$v;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _sessionId;
  String? get sessionId => _$this._sessionId;
  set sessionId(String? sessionId) => _$this._sessionId = sessionId;

  String? _verb;
  String? get verb => _$this._verb;
  set verb(String? verb) => _$this._verb = verb;

  ListBuilder<String>? _itemPids;
  ListBuilder<String> get itemPids =>
      _$this._itemPids ??= ListBuilder<String>();
  set itemPids(ListBuilder<String>? itemPids) => _$this._itemPids = itemPids;

  int? _index;
  int? get index => _$this._index;
  set index(int? index) => _$this._index = index;

  int? _positionMs;
  int? get positionMs => _$this._positionMs;
  set positionMs(int? positionMs) => _$this._positionMs = positionMs;

  bool? _play;
  bool? get play => _$this._play;
  set play(bool? play) => _$this._play = play;

  double? _volume;
  double? get volume => _$this._volume;
  set volume(double? volume) => _$this._volume = volume;

  double? _rate;
  double? get rate => _$this._rate;
  set rate(double? rate) => _$this._rate = rate;

  String? _repeat;
  String? get repeat => _$this._repeat;
  set repeat(String? repeat) => _$this._repeat = repeat;

  bool? _shuffle;
  bool? get shuffle => _$this._shuffle;
  set shuffle(bool? shuffle) => _$this._shuffle = shuffle;

  WsEndpointCommandFrameBuilder() {
    WsEndpointCommandFrame._defaults(this);
  }

  WsEndpointCommandFrameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _id = $v.id;
      _sessionId = $v.sessionId;
      _verb = $v.verb;
      _itemPids = $v.itemPids?.toBuilder();
      _index = $v.index;
      _positionMs = $v.positionMs;
      _play = $v.play;
      _volume = $v.volume;
      _rate = $v.rate;
      _repeat = $v.repeat;
      _shuffle = $v.shuffle;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WsEndpointCommandFrame other) {
    _$v = other as _$WsEndpointCommandFrame;
  }

  @override
  void update(void Function(WsEndpointCommandFrameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WsEndpointCommandFrame build() => _build();

  _$WsEndpointCommandFrame _build() {
    _$WsEndpointCommandFrame _$result;
    try {
      _$result =
          _$v ??
          _$WsEndpointCommandFrame._(
            type: BuiltValueNullFieldError.checkNotNull(
              type,
              r'WsEndpointCommandFrame',
              'type',
            ),
            id: BuiltValueNullFieldError.checkNotNull(
              id,
              r'WsEndpointCommandFrame',
              'id',
            ),
            sessionId: BuiltValueNullFieldError.checkNotNull(
              sessionId,
              r'WsEndpointCommandFrame',
              'sessionId',
            ),
            verb: BuiltValueNullFieldError.checkNotNull(
              verb,
              r'WsEndpointCommandFrame',
              'verb',
            ),
            itemPids: _itemPids?.build(),
            index: index,
            positionMs: positionMs,
            play: play,
            volume: volume,
            rate: rate,
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
          r'WsEndpointCommandFrame',
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
