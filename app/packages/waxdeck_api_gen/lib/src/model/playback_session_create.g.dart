// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playback_session_create.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaybackSessionCreate extends PlaybackSessionCreate {
  @override
  final String endpointId;
  @override
  final BuiltList<String> itemPids;
  @override
  final int? index;
  @override
  final int? positionMs;
  @override
  final bool? play;
  @override
  final double? rate;
  @override
  final String? repeat;
  @override
  final bool? shuffle;
  @override
  final String? handoffFrom;

  factory _$PlaybackSessionCreate([
    void Function(PlaybackSessionCreateBuilder)? updates,
  ]) => (PlaybackSessionCreateBuilder()..update(updates))._build();

  _$PlaybackSessionCreate._({
    required this.endpointId,
    required this.itemPids,
    this.index,
    this.positionMs,
    this.play,
    this.rate,
    this.repeat,
    this.shuffle,
    this.handoffFrom,
  }) : super._();
  @override
  PlaybackSessionCreate rebuild(
    void Function(PlaybackSessionCreateBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PlaybackSessionCreateBuilder toBuilder() =>
      PlaybackSessionCreateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaybackSessionCreate &&
        endpointId == other.endpointId &&
        itemPids == other.itemPids &&
        index == other.index &&
        positionMs == other.positionMs &&
        play == other.play &&
        rate == other.rate &&
        repeat == other.repeat &&
        shuffle == other.shuffle &&
        handoffFrom == other.handoffFrom;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, endpointId.hashCode);
    _$hash = $jc(_$hash, itemPids.hashCode);
    _$hash = $jc(_$hash, index.hashCode);
    _$hash = $jc(_$hash, positionMs.hashCode);
    _$hash = $jc(_$hash, play.hashCode);
    _$hash = $jc(_$hash, rate.hashCode);
    _$hash = $jc(_$hash, repeat.hashCode);
    _$hash = $jc(_$hash, shuffle.hashCode);
    _$hash = $jc(_$hash, handoffFrom.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaybackSessionCreate')
          ..add('endpointId', endpointId)
          ..add('itemPids', itemPids)
          ..add('index', index)
          ..add('positionMs', positionMs)
          ..add('play', play)
          ..add('rate', rate)
          ..add('repeat', repeat)
          ..add('shuffle', shuffle)
          ..add('handoffFrom', handoffFrom))
        .toString();
  }
}

class PlaybackSessionCreateBuilder
    implements Builder<PlaybackSessionCreate, PlaybackSessionCreateBuilder> {
  _$PlaybackSessionCreate? _$v;

  String? _endpointId;
  String? get endpointId => _$this._endpointId;
  set endpointId(String? endpointId) => _$this._endpointId = endpointId;

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

  double? _rate;
  double? get rate => _$this._rate;
  set rate(double? rate) => _$this._rate = rate;

  String? _repeat;
  String? get repeat => _$this._repeat;
  set repeat(String? repeat) => _$this._repeat = repeat;

  bool? _shuffle;
  bool? get shuffle => _$this._shuffle;
  set shuffle(bool? shuffle) => _$this._shuffle = shuffle;

  String? _handoffFrom;
  String? get handoffFrom => _$this._handoffFrom;
  set handoffFrom(String? handoffFrom) => _$this._handoffFrom = handoffFrom;

  PlaybackSessionCreateBuilder() {
    PlaybackSessionCreate._defaults(this);
  }

  PlaybackSessionCreateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _endpointId = $v.endpointId;
      _itemPids = $v.itemPids.toBuilder();
      _index = $v.index;
      _positionMs = $v.positionMs;
      _play = $v.play;
      _rate = $v.rate;
      _repeat = $v.repeat;
      _shuffle = $v.shuffle;
      _handoffFrom = $v.handoffFrom;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaybackSessionCreate other) {
    _$v = other as _$PlaybackSessionCreate;
  }

  @override
  void update(void Function(PlaybackSessionCreateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaybackSessionCreate build() => _build();

  _$PlaybackSessionCreate _build() {
    _$PlaybackSessionCreate _$result;
    try {
      _$result =
          _$v ??
          _$PlaybackSessionCreate._(
            endpointId: BuiltValueNullFieldError.checkNotNull(
              endpointId,
              r'PlaybackSessionCreate',
              'endpointId',
            ),
            itemPids: itemPids.build(),
            index: index,
            positionMs: positionMs,
            play: play,
            rate: rate,
            repeat: repeat,
            shuffle: shuffle,
            handoffFrom: handoffFrom,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'itemPids';
        itemPids.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlaybackSessionCreate',
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
