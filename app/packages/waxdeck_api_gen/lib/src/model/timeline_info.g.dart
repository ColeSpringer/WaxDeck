// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timeline_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TimelineInfo extends TimelineInfo {
  @override
  final String url;
  @override
  final String mimeType;
  @override
  final int durationMs;
  @override
  final DateTime expiresAt;
  @override
  final int envelopeRate;
  @override
  final double? crossfadeSeconds;
  @override
  final String? format;
  @override
  final BuiltList<TimelineBoundary> boundaries;

  factory _$TimelineInfo([void Function(TimelineInfoBuilder)? updates]) =>
      (TimelineInfoBuilder()..update(updates))._build();

  _$TimelineInfo._({
    required this.url,
    required this.mimeType,
    required this.durationMs,
    required this.expiresAt,
    required this.envelopeRate,
    this.crossfadeSeconds,
    this.format,
    required this.boundaries,
  }) : super._();
  @override
  TimelineInfo rebuild(void Function(TimelineInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TimelineInfoBuilder toBuilder() => TimelineInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TimelineInfo &&
        url == other.url &&
        mimeType == other.mimeType &&
        durationMs == other.durationMs &&
        expiresAt == other.expiresAt &&
        envelopeRate == other.envelopeRate &&
        crossfadeSeconds == other.crossfadeSeconds &&
        format == other.format &&
        boundaries == other.boundaries;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, mimeType.hashCode);
    _$hash = $jc(_$hash, durationMs.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jc(_$hash, envelopeRate.hashCode);
    _$hash = $jc(_$hash, crossfadeSeconds.hashCode);
    _$hash = $jc(_$hash, format.hashCode);
    _$hash = $jc(_$hash, boundaries.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TimelineInfo')
          ..add('url', url)
          ..add('mimeType', mimeType)
          ..add('durationMs', durationMs)
          ..add('expiresAt', expiresAt)
          ..add('envelopeRate', envelopeRate)
          ..add('crossfadeSeconds', crossfadeSeconds)
          ..add('format', format)
          ..add('boundaries', boundaries))
        .toString();
  }
}

class TimelineInfoBuilder
    implements Builder<TimelineInfo, TimelineInfoBuilder> {
  _$TimelineInfo? _$v;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  String? _mimeType;
  String? get mimeType => _$this._mimeType;
  set mimeType(String? mimeType) => _$this._mimeType = mimeType;

  int? _durationMs;
  int? get durationMs => _$this._durationMs;
  set durationMs(int? durationMs) => _$this._durationMs = durationMs;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  int? _envelopeRate;
  int? get envelopeRate => _$this._envelopeRate;
  set envelopeRate(int? envelopeRate) => _$this._envelopeRate = envelopeRate;

  double? _crossfadeSeconds;
  double? get crossfadeSeconds => _$this._crossfadeSeconds;
  set crossfadeSeconds(double? crossfadeSeconds) =>
      _$this._crossfadeSeconds = crossfadeSeconds;

  String? _format;
  String? get format => _$this._format;
  set format(String? format) => _$this._format = format;

  ListBuilder<TimelineBoundary>? _boundaries;
  ListBuilder<TimelineBoundary> get boundaries =>
      _$this._boundaries ??= ListBuilder<TimelineBoundary>();
  set boundaries(ListBuilder<TimelineBoundary>? boundaries) =>
      _$this._boundaries = boundaries;

  TimelineInfoBuilder() {
    TimelineInfo._defaults(this);
  }

  TimelineInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _url = $v.url;
      _mimeType = $v.mimeType;
      _durationMs = $v.durationMs;
      _expiresAt = $v.expiresAt;
      _envelopeRate = $v.envelopeRate;
      _crossfadeSeconds = $v.crossfadeSeconds;
      _format = $v.format;
      _boundaries = $v.boundaries.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TimelineInfo other) {
    _$v = other as _$TimelineInfo;
  }

  @override
  void update(void Function(TimelineInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TimelineInfo build() => _build();

  _$TimelineInfo _build() {
    _$TimelineInfo _$result;
    try {
      _$result =
          _$v ??
          _$TimelineInfo._(
            url: BuiltValueNullFieldError.checkNotNull(
              url,
              r'TimelineInfo',
              'url',
            ),
            mimeType: BuiltValueNullFieldError.checkNotNull(
              mimeType,
              r'TimelineInfo',
              'mimeType',
            ),
            durationMs: BuiltValueNullFieldError.checkNotNull(
              durationMs,
              r'TimelineInfo',
              'durationMs',
            ),
            expiresAt: BuiltValueNullFieldError.checkNotNull(
              expiresAt,
              r'TimelineInfo',
              'expiresAt',
            ),
            envelopeRate: BuiltValueNullFieldError.checkNotNull(
              envelopeRate,
              r'TimelineInfo',
              'envelopeRate',
            ),
            crossfadeSeconds: crossfadeSeconds,
            format: format,
            boundaries: boundaries.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'boundaries';
        boundaries.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'TimelineInfo',
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
