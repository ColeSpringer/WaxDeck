// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playback_session_history_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaybackSessionHistoryList extends PlaybackSessionHistoryList {
  @override
  final BuiltList<PlaybackSessionHistoryEntry> sessions;

  factory _$PlaybackSessionHistoryList([
    void Function(PlaybackSessionHistoryListBuilder)? updates,
  ]) => (PlaybackSessionHistoryListBuilder()..update(updates))._build();

  _$PlaybackSessionHistoryList._({required this.sessions}) : super._();
  @override
  PlaybackSessionHistoryList rebuild(
    void Function(PlaybackSessionHistoryListBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PlaybackSessionHistoryListBuilder toBuilder() =>
      PlaybackSessionHistoryListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaybackSessionHistoryList && sessions == other.sessions;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, sessions.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'PlaybackSessionHistoryList',
    )..add('sessions', sessions)).toString();
  }
}

class PlaybackSessionHistoryListBuilder
    implements
        Builder<PlaybackSessionHistoryList, PlaybackSessionHistoryListBuilder> {
  _$PlaybackSessionHistoryList? _$v;

  ListBuilder<PlaybackSessionHistoryEntry>? _sessions;
  ListBuilder<PlaybackSessionHistoryEntry> get sessions =>
      _$this._sessions ??= ListBuilder<PlaybackSessionHistoryEntry>();
  set sessions(ListBuilder<PlaybackSessionHistoryEntry>? sessions) =>
      _$this._sessions = sessions;

  PlaybackSessionHistoryListBuilder() {
    PlaybackSessionHistoryList._defaults(this);
  }

  PlaybackSessionHistoryListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sessions = $v.sessions.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaybackSessionHistoryList other) {
    _$v = other as _$PlaybackSessionHistoryList;
  }

  @override
  void update(void Function(PlaybackSessionHistoryListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaybackSessionHistoryList build() => _build();

  _$PlaybackSessionHistoryList _build() {
    _$PlaybackSessionHistoryList _$result;
    try {
      _$result =
          _$v ?? _$PlaybackSessionHistoryList._(sessions: sessions.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'sessions';
        sessions.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlaybackSessionHistoryList',
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
