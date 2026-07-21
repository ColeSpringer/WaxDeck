// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playback_session_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaybackSessionList extends PlaybackSessionList {
  @override
  final BuiltList<PlaybackSession> sessions;

  factory _$PlaybackSessionList([
    void Function(PlaybackSessionListBuilder)? updates,
  ]) => (PlaybackSessionListBuilder()..update(updates))._build();

  _$PlaybackSessionList._({required this.sessions}) : super._();
  @override
  PlaybackSessionList rebuild(
    void Function(PlaybackSessionListBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PlaybackSessionListBuilder toBuilder() =>
      PlaybackSessionListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaybackSessionList && sessions == other.sessions;
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
      r'PlaybackSessionList',
    )..add('sessions', sessions)).toString();
  }
}

class PlaybackSessionListBuilder
    implements Builder<PlaybackSessionList, PlaybackSessionListBuilder> {
  _$PlaybackSessionList? _$v;

  ListBuilder<PlaybackSession>? _sessions;
  ListBuilder<PlaybackSession> get sessions =>
      _$this._sessions ??= ListBuilder<PlaybackSession>();
  set sessions(ListBuilder<PlaybackSession>? sessions) =>
      _$this._sessions = sessions;

  PlaybackSessionListBuilder() {
    PlaybackSessionList._defaults(this);
  }

  PlaybackSessionListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sessions = $v.sessions.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaybackSessionList other) {
    _$v = other as _$PlaybackSessionList;
  }

  @override
  void update(void Function(PlaybackSessionListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaybackSessionList build() => _build();

  _$PlaybackSessionList _build() {
    _$PlaybackSessionList _$result;
    try {
      _$result = _$v ?? _$PlaybackSessionList._(sessions: sessions.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'sessions';
        sessions.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlaybackSessionList',
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
