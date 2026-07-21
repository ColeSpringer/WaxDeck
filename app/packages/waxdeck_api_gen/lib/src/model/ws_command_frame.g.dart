// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ws_command_frame.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WsCommandFrame extends WsCommandFrame {
  @override
  final String type;
  @override
  final String id;
  @override
  final String sessionId;
  @override
  final String verb;
  @override
  final int? positionMs;
  @override
  final double? volume;
  @override
  final double? rate;
  @override
  final BuiltList<String>? itemPids;
  @override
  final int? index;
  @override
  final String? repeat;
  @override
  final bool? shuffle;

  factory _$WsCommandFrame([void Function(WsCommandFrameBuilder)? updates]) =>
      (WsCommandFrameBuilder()..update(updates))._build();

  _$WsCommandFrame._({
    required this.type,
    required this.id,
    required this.sessionId,
    required this.verb,
    this.positionMs,
    this.volume,
    this.rate,
    this.itemPids,
    this.index,
    this.repeat,
    this.shuffle,
  }) : super._();
  @override
  WsCommandFrame rebuild(void Function(WsCommandFrameBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WsCommandFrameBuilder toBuilder() => WsCommandFrameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WsCommandFrame &&
        type == other.type &&
        id == other.id &&
        sessionId == other.sessionId &&
        verb == other.verb &&
        positionMs == other.positionMs &&
        volume == other.volume &&
        rate == other.rate &&
        itemPids == other.itemPids &&
        index == other.index &&
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
    _$hash = $jc(_$hash, positionMs.hashCode);
    _$hash = $jc(_$hash, volume.hashCode);
    _$hash = $jc(_$hash, rate.hashCode);
    _$hash = $jc(_$hash, itemPids.hashCode);
    _$hash = $jc(_$hash, index.hashCode);
    _$hash = $jc(_$hash, repeat.hashCode);
    _$hash = $jc(_$hash, shuffle.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WsCommandFrame')
          ..add('type', type)
          ..add('id', id)
          ..add('sessionId', sessionId)
          ..add('verb', verb)
          ..add('positionMs', positionMs)
          ..add('volume', volume)
          ..add('rate', rate)
          ..add('itemPids', itemPids)
          ..add('index', index)
          ..add('repeat', repeat)
          ..add('shuffle', shuffle))
        .toString();
  }
}

class WsCommandFrameBuilder
    implements Builder<WsCommandFrame, WsCommandFrameBuilder> {
  _$WsCommandFrame? _$v;

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

  int? _positionMs;
  int? get positionMs => _$this._positionMs;
  set positionMs(int? positionMs) => _$this._positionMs = positionMs;

  double? _volume;
  double? get volume => _$this._volume;
  set volume(double? volume) => _$this._volume = volume;

  double? _rate;
  double? get rate => _$this._rate;
  set rate(double? rate) => _$this._rate = rate;

  ListBuilder<String>? _itemPids;
  ListBuilder<String> get itemPids =>
      _$this._itemPids ??= ListBuilder<String>();
  set itemPids(ListBuilder<String>? itemPids) => _$this._itemPids = itemPids;

  int? _index;
  int? get index => _$this._index;
  set index(int? index) => _$this._index = index;

  String? _repeat;
  String? get repeat => _$this._repeat;
  set repeat(String? repeat) => _$this._repeat = repeat;

  bool? _shuffle;
  bool? get shuffle => _$this._shuffle;
  set shuffle(bool? shuffle) => _$this._shuffle = shuffle;

  WsCommandFrameBuilder() {
    WsCommandFrame._defaults(this);
  }

  WsCommandFrameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _id = $v.id;
      _sessionId = $v.sessionId;
      _verb = $v.verb;
      _positionMs = $v.positionMs;
      _volume = $v.volume;
      _rate = $v.rate;
      _itemPids = $v.itemPids?.toBuilder();
      _index = $v.index;
      _repeat = $v.repeat;
      _shuffle = $v.shuffle;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WsCommandFrame other) {
    _$v = other as _$WsCommandFrame;
  }

  @override
  void update(void Function(WsCommandFrameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WsCommandFrame build() => _build();

  _$WsCommandFrame _build() {
    _$WsCommandFrame _$result;
    try {
      _$result =
          _$v ??
          _$WsCommandFrame._(
            type: BuiltValueNullFieldError.checkNotNull(
              type,
              r'WsCommandFrame',
              'type',
            ),
            id: BuiltValueNullFieldError.checkNotNull(
              id,
              r'WsCommandFrame',
              'id',
            ),
            sessionId: BuiltValueNullFieldError.checkNotNull(
              sessionId,
              r'WsCommandFrame',
              'sessionId',
            ),
            verb: BuiltValueNullFieldError.checkNotNull(
              verb,
              r'WsCommandFrame',
              'verb',
            ),
            positionMs: positionMs,
            volume: volume,
            rate: rate,
            itemPids: _itemPids?.build(),
            index: index,
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
          r'WsCommandFrame',
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
