// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playback_session.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaybackSession extends PlaybackSession {
  @override
  final String id;
  @override
  final String endpointId;
  @override
  final String? endpointName;
  @override
  final bool mine;
  @override
  final String? ownerName;
  @override
  final String authority;
  @override
  final bool playing;
  @override
  final int index;
  @override
  final int positionMs;
  @override
  final DateTime positionAt;
  @override
  final double rate;
  @override
  final double? volume;
  @override
  final String? repeat;
  @override
  final bool? shuffle;
  @override
  final int queueVersion;
  @override
  final BuiltList<PlaybackSessionEntry>? entries;
  @override
  final bool? ended;
  @override
  final DateTime updatedAt;

  factory _$PlaybackSession([void Function(PlaybackSessionBuilder)? updates]) =>
      (PlaybackSessionBuilder()..update(updates))._build();

  _$PlaybackSession._({
    required this.id,
    required this.endpointId,
    this.endpointName,
    required this.mine,
    this.ownerName,
    required this.authority,
    required this.playing,
    required this.index,
    required this.positionMs,
    required this.positionAt,
    required this.rate,
    this.volume,
    this.repeat,
    this.shuffle,
    required this.queueVersion,
    this.entries,
    this.ended,
    required this.updatedAt,
  }) : super._();
  @override
  PlaybackSession rebuild(void Function(PlaybackSessionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlaybackSessionBuilder toBuilder() => PlaybackSessionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaybackSession &&
        id == other.id &&
        endpointId == other.endpointId &&
        endpointName == other.endpointName &&
        mine == other.mine &&
        ownerName == other.ownerName &&
        authority == other.authority &&
        playing == other.playing &&
        index == other.index &&
        positionMs == other.positionMs &&
        positionAt == other.positionAt &&
        rate == other.rate &&
        volume == other.volume &&
        repeat == other.repeat &&
        shuffle == other.shuffle &&
        queueVersion == other.queueVersion &&
        entries == other.entries &&
        ended == other.ended &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, endpointId.hashCode);
    _$hash = $jc(_$hash, endpointName.hashCode);
    _$hash = $jc(_$hash, mine.hashCode);
    _$hash = $jc(_$hash, ownerName.hashCode);
    _$hash = $jc(_$hash, authority.hashCode);
    _$hash = $jc(_$hash, playing.hashCode);
    _$hash = $jc(_$hash, index.hashCode);
    _$hash = $jc(_$hash, positionMs.hashCode);
    _$hash = $jc(_$hash, positionAt.hashCode);
    _$hash = $jc(_$hash, rate.hashCode);
    _$hash = $jc(_$hash, volume.hashCode);
    _$hash = $jc(_$hash, repeat.hashCode);
    _$hash = $jc(_$hash, shuffle.hashCode);
    _$hash = $jc(_$hash, queueVersion.hashCode);
    _$hash = $jc(_$hash, entries.hashCode);
    _$hash = $jc(_$hash, ended.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaybackSession')
          ..add('id', id)
          ..add('endpointId', endpointId)
          ..add('endpointName', endpointName)
          ..add('mine', mine)
          ..add('ownerName', ownerName)
          ..add('authority', authority)
          ..add('playing', playing)
          ..add('index', index)
          ..add('positionMs', positionMs)
          ..add('positionAt', positionAt)
          ..add('rate', rate)
          ..add('volume', volume)
          ..add('repeat', repeat)
          ..add('shuffle', shuffle)
          ..add('queueVersion', queueVersion)
          ..add('entries', entries)
          ..add('ended', ended)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class PlaybackSessionBuilder
    implements Builder<PlaybackSession, PlaybackSessionBuilder> {
  _$PlaybackSession? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _endpointId;
  String? get endpointId => _$this._endpointId;
  set endpointId(String? endpointId) => _$this._endpointId = endpointId;

  String? _endpointName;
  String? get endpointName => _$this._endpointName;
  set endpointName(String? endpointName) => _$this._endpointName = endpointName;

  bool? _mine;
  bool? get mine => _$this._mine;
  set mine(bool? mine) => _$this._mine = mine;

  String? _ownerName;
  String? get ownerName => _$this._ownerName;
  set ownerName(String? ownerName) => _$this._ownerName = ownerName;

  String? _authority;
  String? get authority => _$this._authority;
  set authority(String? authority) => _$this._authority = authority;

  bool? _playing;
  bool? get playing => _$this._playing;
  set playing(bool? playing) => _$this._playing = playing;

  int? _index;
  int? get index => _$this._index;
  set index(int? index) => _$this._index = index;

  int? _positionMs;
  int? get positionMs => _$this._positionMs;
  set positionMs(int? positionMs) => _$this._positionMs = positionMs;

  DateTime? _positionAt;
  DateTime? get positionAt => _$this._positionAt;
  set positionAt(DateTime? positionAt) => _$this._positionAt = positionAt;

  double? _rate;
  double? get rate => _$this._rate;
  set rate(double? rate) => _$this._rate = rate;

  double? _volume;
  double? get volume => _$this._volume;
  set volume(double? volume) => _$this._volume = volume;

  String? _repeat;
  String? get repeat => _$this._repeat;
  set repeat(String? repeat) => _$this._repeat = repeat;

  bool? _shuffle;
  bool? get shuffle => _$this._shuffle;
  set shuffle(bool? shuffle) => _$this._shuffle = shuffle;

  int? _queueVersion;
  int? get queueVersion => _$this._queueVersion;
  set queueVersion(int? queueVersion) => _$this._queueVersion = queueVersion;

  ListBuilder<PlaybackSessionEntry>? _entries;
  ListBuilder<PlaybackSessionEntry> get entries =>
      _$this._entries ??= ListBuilder<PlaybackSessionEntry>();
  set entries(ListBuilder<PlaybackSessionEntry>? entries) =>
      _$this._entries = entries;

  bool? _ended;
  bool? get ended => _$this._ended;
  set ended(bool? ended) => _$this._ended = ended;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  PlaybackSessionBuilder() {
    PlaybackSession._defaults(this);
  }

  PlaybackSessionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _endpointId = $v.endpointId;
      _endpointName = $v.endpointName;
      _mine = $v.mine;
      _ownerName = $v.ownerName;
      _authority = $v.authority;
      _playing = $v.playing;
      _index = $v.index;
      _positionMs = $v.positionMs;
      _positionAt = $v.positionAt;
      _rate = $v.rate;
      _volume = $v.volume;
      _repeat = $v.repeat;
      _shuffle = $v.shuffle;
      _queueVersion = $v.queueVersion;
      _entries = $v.entries?.toBuilder();
      _ended = $v.ended;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaybackSession other) {
    _$v = other as _$PlaybackSession;
  }

  @override
  void update(void Function(PlaybackSessionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaybackSession build() => _build();

  _$PlaybackSession _build() {
    _$PlaybackSession _$result;
    try {
      _$result =
          _$v ??
          _$PlaybackSession._(
            id: BuiltValueNullFieldError.checkNotNull(
              id,
              r'PlaybackSession',
              'id',
            ),
            endpointId: BuiltValueNullFieldError.checkNotNull(
              endpointId,
              r'PlaybackSession',
              'endpointId',
            ),
            endpointName: endpointName,
            mine: BuiltValueNullFieldError.checkNotNull(
              mine,
              r'PlaybackSession',
              'mine',
            ),
            ownerName: ownerName,
            authority: BuiltValueNullFieldError.checkNotNull(
              authority,
              r'PlaybackSession',
              'authority',
            ),
            playing: BuiltValueNullFieldError.checkNotNull(
              playing,
              r'PlaybackSession',
              'playing',
            ),
            index: BuiltValueNullFieldError.checkNotNull(
              index,
              r'PlaybackSession',
              'index',
            ),
            positionMs: BuiltValueNullFieldError.checkNotNull(
              positionMs,
              r'PlaybackSession',
              'positionMs',
            ),
            positionAt: BuiltValueNullFieldError.checkNotNull(
              positionAt,
              r'PlaybackSession',
              'positionAt',
            ),
            rate: BuiltValueNullFieldError.checkNotNull(
              rate,
              r'PlaybackSession',
              'rate',
            ),
            volume: volume,
            repeat: repeat,
            shuffle: shuffle,
            queueVersion: BuiltValueNullFieldError.checkNotNull(
              queueVersion,
              r'PlaybackSession',
              'queueVersion',
            ),
            entries: _entries?.build(),
            ended: ended,
            updatedAt: BuiltValueNullFieldError.checkNotNull(
              updatedAt,
              r'PlaybackSession',
              'updatedAt',
            ),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entries';
        _entries?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlaybackSession',
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
