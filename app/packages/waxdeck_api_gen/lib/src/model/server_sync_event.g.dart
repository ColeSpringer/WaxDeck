// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_sync_event.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ServerSyncEvent extends ServerSyncEvent {
  @override
  final String kind;
  @override
  final String? pid;
  @override
  final PlayState? playState;
  @override
  final Prefs? prefs;
  @override
  final Subscription? subscription;
  @override
  final BookSettings? bookSettings;
  @override
  final Playlist? playlist;

  factory _$ServerSyncEvent([void Function(ServerSyncEventBuilder)? updates]) =>
      (ServerSyncEventBuilder()..update(updates))._build();

  _$ServerSyncEvent._({
    required this.kind,
    this.pid,
    this.playState,
    this.prefs,
    this.subscription,
    this.bookSettings,
    this.playlist,
  }) : super._();
  @override
  ServerSyncEvent rebuild(void Function(ServerSyncEventBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ServerSyncEventBuilder toBuilder() => ServerSyncEventBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServerSyncEvent &&
        kind == other.kind &&
        pid == other.pid &&
        playState == other.playState &&
        prefs == other.prefs &&
        subscription == other.subscription &&
        bookSettings == other.bookSettings &&
        playlist == other.playlist;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, playState.hashCode);
    _$hash = $jc(_$hash, prefs.hashCode);
    _$hash = $jc(_$hash, subscription.hashCode);
    _$hash = $jc(_$hash, bookSettings.hashCode);
    _$hash = $jc(_$hash, playlist.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ServerSyncEvent')
          ..add('kind', kind)
          ..add('pid', pid)
          ..add('playState', playState)
          ..add('prefs', prefs)
          ..add('subscription', subscription)
          ..add('bookSettings', bookSettings)
          ..add('playlist', playlist))
        .toString();
  }
}

class ServerSyncEventBuilder
    implements Builder<ServerSyncEvent, ServerSyncEventBuilder> {
  _$ServerSyncEvent? _$v;

  String? _kind;
  String? get kind => _$this._kind;
  set kind(String? kind) => _$this._kind = kind;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  PlayStateBuilder? _playState;
  PlayStateBuilder get playState => _$this._playState ??= PlayStateBuilder();
  set playState(PlayStateBuilder? playState) => _$this._playState = playState;

  PrefsBuilder? _prefs;
  PrefsBuilder get prefs => _$this._prefs ??= PrefsBuilder();
  set prefs(PrefsBuilder? prefs) => _$this._prefs = prefs;

  SubscriptionBuilder? _subscription;
  SubscriptionBuilder get subscription =>
      _$this._subscription ??= SubscriptionBuilder();
  set subscription(SubscriptionBuilder? subscription) =>
      _$this._subscription = subscription;

  BookSettingsBuilder? _bookSettings;
  BookSettingsBuilder get bookSettings =>
      _$this._bookSettings ??= BookSettingsBuilder();
  set bookSettings(BookSettingsBuilder? bookSettings) =>
      _$this._bookSettings = bookSettings;

  PlaylistBuilder? _playlist;
  PlaylistBuilder get playlist => _$this._playlist ??= PlaylistBuilder();
  set playlist(PlaylistBuilder? playlist) => _$this._playlist = playlist;

  ServerSyncEventBuilder() {
    ServerSyncEvent._defaults(this);
  }

  ServerSyncEventBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _pid = $v.pid;
      _playState = $v.playState?.toBuilder();
      _prefs = $v.prefs?.toBuilder();
      _subscription = $v.subscription?.toBuilder();
      _bookSettings = $v.bookSettings?.toBuilder();
      _playlist = $v.playlist?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServerSyncEvent other) {
    _$v = other as _$ServerSyncEvent;
  }

  @override
  void update(void Function(ServerSyncEventBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ServerSyncEvent build() => _build();

  _$ServerSyncEvent _build() {
    _$ServerSyncEvent _$result;
    try {
      _$result =
          _$v ??
          _$ServerSyncEvent._(
            kind: BuiltValueNullFieldError.checkNotNull(
              kind,
              r'ServerSyncEvent',
              'kind',
            ),
            pid: pid,
            playState: _playState?.build(),
            prefs: _prefs?.build(),
            subscription: _subscription?.build(),
            bookSettings: _bookSettings?.build(),
            playlist: _playlist?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'playState';
        _playState?.build();
        _$failedField = 'prefs';
        _prefs?.build();
        _$failedField = 'subscription';
        _subscription?.build();
        _$failedField = 'bookSettings';
        _bookSettings?.build();
        _$failedField = 'playlist';
        _playlist?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ServerSyncEvent',
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
