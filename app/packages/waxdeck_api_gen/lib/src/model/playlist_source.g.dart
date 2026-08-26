// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_source.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaylistSource extends PlaylistSource {
  @override
  final String source_;
  @override
  final String? url;
  @override
  final String? title;
  @override
  final bool live;
  @override
  final String mode;
  @override
  final int? intervalHours;
  @override
  final int? refCount;
  @override
  final bool disabled;
  @override
  final int consecutiveFailures;
  @override
  final String? lastError;
  @override
  final DateTime? lastAttemptAt;
  @override
  final DateTime? lastSyncedAt;
  @override
  final PlaylistSyncCounts? lastRun;

  factory _$PlaylistSource([void Function(PlaylistSourceBuilder)? updates]) =>
      (PlaylistSourceBuilder()..update(updates))._build();

  _$PlaylistSource._({
    required this.source_,
    this.url,
    this.title,
    required this.live,
    required this.mode,
    this.intervalHours,
    this.refCount,
    required this.disabled,
    required this.consecutiveFailures,
    this.lastError,
    this.lastAttemptAt,
    this.lastSyncedAt,
    this.lastRun,
  }) : super._();
  @override
  PlaylistSource rebuild(void Function(PlaylistSourceBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlaylistSourceBuilder toBuilder() => PlaylistSourceBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaylistSource &&
        source_ == other.source_ &&
        url == other.url &&
        title == other.title &&
        live == other.live &&
        mode == other.mode &&
        intervalHours == other.intervalHours &&
        refCount == other.refCount &&
        disabled == other.disabled &&
        consecutiveFailures == other.consecutiveFailures &&
        lastError == other.lastError &&
        lastAttemptAt == other.lastAttemptAt &&
        lastSyncedAt == other.lastSyncedAt &&
        lastRun == other.lastRun;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, live.hashCode);
    _$hash = $jc(_$hash, mode.hashCode);
    _$hash = $jc(_$hash, intervalHours.hashCode);
    _$hash = $jc(_$hash, refCount.hashCode);
    _$hash = $jc(_$hash, disabled.hashCode);
    _$hash = $jc(_$hash, consecutiveFailures.hashCode);
    _$hash = $jc(_$hash, lastError.hashCode);
    _$hash = $jc(_$hash, lastAttemptAt.hashCode);
    _$hash = $jc(_$hash, lastSyncedAt.hashCode);
    _$hash = $jc(_$hash, lastRun.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaylistSource')
          ..add('source_', source_)
          ..add('url', url)
          ..add('title', title)
          ..add('live', live)
          ..add('mode', mode)
          ..add('intervalHours', intervalHours)
          ..add('refCount', refCount)
          ..add('disabled', disabled)
          ..add('consecutiveFailures', consecutiveFailures)
          ..add('lastError', lastError)
          ..add('lastAttemptAt', lastAttemptAt)
          ..add('lastSyncedAt', lastSyncedAt)
          ..add('lastRun', lastRun))
        .toString();
  }
}

class PlaylistSourceBuilder
    implements Builder<PlaylistSource, PlaylistSourceBuilder> {
  _$PlaylistSource? _$v;

  String? _source_;
  String? get source_ => _$this._source_;
  set source_(String? source_) => _$this._source_ = source_;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  bool? _live;
  bool? get live => _$this._live;
  set live(bool? live) => _$this._live = live;

  String? _mode;
  String? get mode => _$this._mode;
  set mode(String? mode) => _$this._mode = mode;

  int? _intervalHours;
  int? get intervalHours => _$this._intervalHours;
  set intervalHours(int? intervalHours) =>
      _$this._intervalHours = intervalHours;

  int? _refCount;
  int? get refCount => _$this._refCount;
  set refCount(int? refCount) => _$this._refCount = refCount;

  bool? _disabled;
  bool? get disabled => _$this._disabled;
  set disabled(bool? disabled) => _$this._disabled = disabled;

  int? _consecutiveFailures;
  int? get consecutiveFailures => _$this._consecutiveFailures;
  set consecutiveFailures(int? consecutiveFailures) =>
      _$this._consecutiveFailures = consecutiveFailures;

  String? _lastError;
  String? get lastError => _$this._lastError;
  set lastError(String? lastError) => _$this._lastError = lastError;

  DateTime? _lastAttemptAt;
  DateTime? get lastAttemptAt => _$this._lastAttemptAt;
  set lastAttemptAt(DateTime? lastAttemptAt) =>
      _$this._lastAttemptAt = lastAttemptAt;

  DateTime? _lastSyncedAt;
  DateTime? get lastSyncedAt => _$this._lastSyncedAt;
  set lastSyncedAt(DateTime? lastSyncedAt) =>
      _$this._lastSyncedAt = lastSyncedAt;

  PlaylistSyncCountsBuilder? _lastRun;
  PlaylistSyncCountsBuilder get lastRun =>
      _$this._lastRun ??= PlaylistSyncCountsBuilder();
  set lastRun(PlaylistSyncCountsBuilder? lastRun) => _$this._lastRun = lastRun;

  PlaylistSourceBuilder() {
    PlaylistSource._defaults(this);
  }

  PlaylistSourceBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _source_ = $v.source_;
      _url = $v.url;
      _title = $v.title;
      _live = $v.live;
      _mode = $v.mode;
      _intervalHours = $v.intervalHours;
      _refCount = $v.refCount;
      _disabled = $v.disabled;
      _consecutiveFailures = $v.consecutiveFailures;
      _lastError = $v.lastError;
      _lastAttemptAt = $v.lastAttemptAt;
      _lastSyncedAt = $v.lastSyncedAt;
      _lastRun = $v.lastRun?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaylistSource other) {
    _$v = other as _$PlaylistSource;
  }

  @override
  void update(void Function(PlaylistSourceBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaylistSource build() => _build();

  _$PlaylistSource _build() {
    _$PlaylistSource _$result;
    try {
      _$result =
          _$v ??
          _$PlaylistSource._(
            source_: BuiltValueNullFieldError.checkNotNull(
              source_,
              r'PlaylistSource',
              'source_',
            ),
            url: url,
            title: title,
            live: BuiltValueNullFieldError.checkNotNull(
              live,
              r'PlaylistSource',
              'live',
            ),
            mode: BuiltValueNullFieldError.checkNotNull(
              mode,
              r'PlaylistSource',
              'mode',
            ),
            intervalHours: intervalHours,
            refCount: refCount,
            disabled: BuiltValueNullFieldError.checkNotNull(
              disabled,
              r'PlaylistSource',
              'disabled',
            ),
            consecutiveFailures: BuiltValueNullFieldError.checkNotNull(
              consecutiveFailures,
              r'PlaylistSource',
              'consecutiveFailures',
            ),
            lastError: lastError,
            lastAttemptAt: lastAttemptAt,
            lastSyncedAt: lastSyncedAt,
            lastRun: _lastRun?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'lastRun';
        _lastRun?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlaylistSource',
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
