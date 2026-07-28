// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playback_session_history_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaybackSessionHistoryEntry extends PlaybackSessionHistoryEntry {
  @override
  final String id;
  @override
  final String endpointId;
  @override
  final String? endpointName;
  @override
  final String authority;
  @override
  final int index;
  @override
  final int positionMs;
  @override
  final DateTime positionAt;
  @override
  final double rate;
  @override
  final String? repeat;
  @override
  final bool? shuffle;
  @override
  final BuiltList<PlaybackSessionEntry> entries;

  factory _$PlaybackSessionHistoryEntry([
    void Function(PlaybackSessionHistoryEntryBuilder)? updates,
  ]) => (PlaybackSessionHistoryEntryBuilder()..update(updates))._build();

  _$PlaybackSessionHistoryEntry._({
    required this.id,
    required this.endpointId,
    this.endpointName,
    required this.authority,
    required this.index,
    required this.positionMs,
    required this.positionAt,
    required this.rate,
    this.repeat,
    this.shuffle,
    required this.entries,
  }) : super._();
  @override
  PlaybackSessionHistoryEntry rebuild(
    void Function(PlaybackSessionHistoryEntryBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PlaybackSessionHistoryEntryBuilder toBuilder() =>
      PlaybackSessionHistoryEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaybackSessionHistoryEntry &&
        id == other.id &&
        endpointId == other.endpointId &&
        endpointName == other.endpointName &&
        authority == other.authority &&
        index == other.index &&
        positionMs == other.positionMs &&
        positionAt == other.positionAt &&
        rate == other.rate &&
        repeat == other.repeat &&
        shuffle == other.shuffle &&
        entries == other.entries;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, endpointId.hashCode);
    _$hash = $jc(_$hash, endpointName.hashCode);
    _$hash = $jc(_$hash, authority.hashCode);
    _$hash = $jc(_$hash, index.hashCode);
    _$hash = $jc(_$hash, positionMs.hashCode);
    _$hash = $jc(_$hash, positionAt.hashCode);
    _$hash = $jc(_$hash, rate.hashCode);
    _$hash = $jc(_$hash, repeat.hashCode);
    _$hash = $jc(_$hash, shuffle.hashCode);
    _$hash = $jc(_$hash, entries.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaybackSessionHistoryEntry')
          ..add('id', id)
          ..add('endpointId', endpointId)
          ..add('endpointName', endpointName)
          ..add('authority', authority)
          ..add('index', index)
          ..add('positionMs', positionMs)
          ..add('positionAt', positionAt)
          ..add('rate', rate)
          ..add('repeat', repeat)
          ..add('shuffle', shuffle)
          ..add('entries', entries))
        .toString();
  }
}

class PlaybackSessionHistoryEntryBuilder
    implements
        Builder<
          PlaybackSessionHistoryEntry,
          PlaybackSessionHistoryEntryBuilder
        > {
  _$PlaybackSessionHistoryEntry? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _endpointId;
  String? get endpointId => _$this._endpointId;
  set endpointId(String? endpointId) => _$this._endpointId = endpointId;

  String? _endpointName;
  String? get endpointName => _$this._endpointName;
  set endpointName(String? endpointName) => _$this._endpointName = endpointName;

  String? _authority;
  String? get authority => _$this._authority;
  set authority(String? authority) => _$this._authority = authority;

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

  String? _repeat;
  String? get repeat => _$this._repeat;
  set repeat(String? repeat) => _$this._repeat = repeat;

  bool? _shuffle;
  bool? get shuffle => _$this._shuffle;
  set shuffle(bool? shuffle) => _$this._shuffle = shuffle;

  ListBuilder<PlaybackSessionEntry>? _entries;
  ListBuilder<PlaybackSessionEntry> get entries =>
      _$this._entries ??= ListBuilder<PlaybackSessionEntry>();
  set entries(ListBuilder<PlaybackSessionEntry>? entries) =>
      _$this._entries = entries;

  PlaybackSessionHistoryEntryBuilder() {
    PlaybackSessionHistoryEntry._defaults(this);
  }

  PlaybackSessionHistoryEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _endpointId = $v.endpointId;
      _endpointName = $v.endpointName;
      _authority = $v.authority;
      _index = $v.index;
      _positionMs = $v.positionMs;
      _positionAt = $v.positionAt;
      _rate = $v.rate;
      _repeat = $v.repeat;
      _shuffle = $v.shuffle;
      _entries = $v.entries.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaybackSessionHistoryEntry other) {
    _$v = other as _$PlaybackSessionHistoryEntry;
  }

  @override
  void update(void Function(PlaybackSessionHistoryEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaybackSessionHistoryEntry build() => _build();

  _$PlaybackSessionHistoryEntry _build() {
    _$PlaybackSessionHistoryEntry _$result;
    try {
      _$result =
          _$v ??
          _$PlaybackSessionHistoryEntry._(
            id: BuiltValueNullFieldError.checkNotNull(
              id,
              r'PlaybackSessionHistoryEntry',
              'id',
            ),
            endpointId: BuiltValueNullFieldError.checkNotNull(
              endpointId,
              r'PlaybackSessionHistoryEntry',
              'endpointId',
            ),
            endpointName: endpointName,
            authority: BuiltValueNullFieldError.checkNotNull(
              authority,
              r'PlaybackSessionHistoryEntry',
              'authority',
            ),
            index: BuiltValueNullFieldError.checkNotNull(
              index,
              r'PlaybackSessionHistoryEntry',
              'index',
            ),
            positionMs: BuiltValueNullFieldError.checkNotNull(
              positionMs,
              r'PlaybackSessionHistoryEntry',
              'positionMs',
            ),
            positionAt: BuiltValueNullFieldError.checkNotNull(
              positionAt,
              r'PlaybackSessionHistoryEntry',
              'positionAt',
            ),
            rate: BuiltValueNullFieldError.checkNotNull(
              rate,
              r'PlaybackSessionHistoryEntry',
              'rate',
            ),
            repeat: repeat,
            shuffle: shuffle,
            entries: entries.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entries';
        entries.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlaybackSessionHistoryEntry',
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
