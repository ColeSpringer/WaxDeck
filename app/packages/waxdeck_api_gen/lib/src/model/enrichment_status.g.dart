// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrichment_status.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichmentStatus extends EnrichmentStatus {
  @override
  final BuiltList<EnrichmentProvider> providers;
  @override
  final EnrichmentCoverage coverage;
  @override
  final bool running;
  @override
  final bool configured;
  @override
  final EnrichmentLastRun? lastRun;

  factory _$EnrichmentStatus([
    void Function(EnrichmentStatusBuilder)? updates,
  ]) => (EnrichmentStatusBuilder()..update(updates))._build();

  _$EnrichmentStatus._({
    required this.providers,
    required this.coverage,
    required this.running,
    required this.configured,
    this.lastRun,
  }) : super._();
  @override
  EnrichmentStatus rebuild(void Function(EnrichmentStatusBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EnrichmentStatusBuilder toBuilder() =>
      EnrichmentStatusBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichmentStatus &&
        providers == other.providers &&
        coverage == other.coverage &&
        running == other.running &&
        configured == other.configured &&
        lastRun == other.lastRun;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, providers.hashCode);
    _$hash = $jc(_$hash, coverage.hashCode);
    _$hash = $jc(_$hash, running.hashCode);
    _$hash = $jc(_$hash, configured.hashCode);
    _$hash = $jc(_$hash, lastRun.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EnrichmentStatus')
          ..add('providers', providers)
          ..add('coverage', coverage)
          ..add('running', running)
          ..add('configured', configured)
          ..add('lastRun', lastRun))
        .toString();
  }
}

class EnrichmentStatusBuilder
    implements Builder<EnrichmentStatus, EnrichmentStatusBuilder> {
  _$EnrichmentStatus? _$v;

  ListBuilder<EnrichmentProvider>? _providers;
  ListBuilder<EnrichmentProvider> get providers =>
      _$this._providers ??= ListBuilder<EnrichmentProvider>();
  set providers(ListBuilder<EnrichmentProvider>? providers) =>
      _$this._providers = providers;

  EnrichmentCoverageBuilder? _coverage;
  EnrichmentCoverageBuilder get coverage =>
      _$this._coverage ??= EnrichmentCoverageBuilder();
  set coverage(EnrichmentCoverageBuilder? coverage) =>
      _$this._coverage = coverage;

  bool? _running;
  bool? get running => _$this._running;
  set running(bool? running) => _$this._running = running;

  bool? _configured;
  bool? get configured => _$this._configured;
  set configured(bool? configured) => _$this._configured = configured;

  EnrichmentLastRunBuilder? _lastRun;
  EnrichmentLastRunBuilder get lastRun =>
      _$this._lastRun ??= EnrichmentLastRunBuilder();
  set lastRun(EnrichmentLastRunBuilder? lastRun) => _$this._lastRun = lastRun;

  EnrichmentStatusBuilder() {
    EnrichmentStatus._defaults(this);
  }

  EnrichmentStatusBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _providers = $v.providers.toBuilder();
      _coverage = $v.coverage.toBuilder();
      _running = $v.running;
      _configured = $v.configured;
      _lastRun = $v.lastRun?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichmentStatus other) {
    _$v = other as _$EnrichmentStatus;
  }

  @override
  void update(void Function(EnrichmentStatusBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichmentStatus build() => _build();

  _$EnrichmentStatus _build() {
    _$EnrichmentStatus _$result;
    try {
      _$result =
          _$v ??
          _$EnrichmentStatus._(
            providers: providers.build(),
            coverage: coverage.build(),
            running: BuiltValueNullFieldError.checkNotNull(
              running,
              r'EnrichmentStatus',
              'running',
            ),
            configured: BuiltValueNullFieldError.checkNotNull(
              configured,
              r'EnrichmentStatus',
              'configured',
            ),
            lastRun: _lastRun?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'providers';
        providers.build();
        _$failedField = 'coverage';
        coverage.build();

        _$failedField = 'lastRun';
        _lastRun?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EnrichmentStatus',
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
