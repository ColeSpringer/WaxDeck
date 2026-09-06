// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrichment_status.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const EnrichmentStatusPhasesEnum _$enrichmentStatusPhasesEnum_identity =
    const EnrichmentStatusPhasesEnum._('identity');
const EnrichmentStatusPhasesEnum _$enrichmentStatusPhasesEnum_releases =
    const EnrichmentStatusPhasesEnum._('releases');
const EnrichmentStatusPhasesEnum _$enrichmentStatusPhasesEnum_auxArt =
    const EnrichmentStatusPhasesEnum._('auxArt');
const EnrichmentStatusPhasesEnum _$enrichmentStatusPhasesEnum_artistArt =
    const EnrichmentStatusPhasesEnum._('artistArt');
const EnrichmentStatusPhasesEnum _$enrichmentStatusPhasesEnum_lyrics =
    const EnrichmentStatusPhasesEnum._('lyrics');
const EnrichmentStatusPhasesEnum _$enrichmentStatusPhasesEnum_trackFields =
    const EnrichmentStatusPhasesEnum._('trackFields');
const EnrichmentStatusPhasesEnum _$enrichmentStatusPhasesEnum_bookFields =
    const EnrichmentStatusPhasesEnum._('bookFields');
const EnrichmentStatusPhasesEnum _$enrichmentStatusPhasesEnum_albumFields =
    const EnrichmentStatusPhasesEnum._('albumFields');
const EnrichmentStatusPhasesEnum
_$enrichmentStatusPhasesEnum_unknownDefaultOpenApi =
    const EnrichmentStatusPhasesEnum._('unknownDefaultOpenApi');

EnrichmentStatusPhasesEnum _$enrichmentStatusPhasesEnumValueOf(String name) {
  switch (name) {
    case 'identity':
      return _$enrichmentStatusPhasesEnum_identity;
    case 'releases':
      return _$enrichmentStatusPhasesEnum_releases;
    case 'auxArt':
      return _$enrichmentStatusPhasesEnum_auxArt;
    case 'artistArt':
      return _$enrichmentStatusPhasesEnum_artistArt;
    case 'lyrics':
      return _$enrichmentStatusPhasesEnum_lyrics;
    case 'trackFields':
      return _$enrichmentStatusPhasesEnum_trackFields;
    case 'bookFields':
      return _$enrichmentStatusPhasesEnum_bookFields;
    case 'albumFields':
      return _$enrichmentStatusPhasesEnum_albumFields;
    case 'unknownDefaultOpenApi':
      return _$enrichmentStatusPhasesEnum_unknownDefaultOpenApi;
    default:
      return _$enrichmentStatusPhasesEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<EnrichmentStatusPhasesEnum> _$enrichmentStatusPhasesEnumValues =
    BuiltSet<EnrichmentStatusPhasesEnum>(const <EnrichmentStatusPhasesEnum>[
      _$enrichmentStatusPhasesEnum_identity,
      _$enrichmentStatusPhasesEnum_releases,
      _$enrichmentStatusPhasesEnum_auxArt,
      _$enrichmentStatusPhasesEnum_artistArt,
      _$enrichmentStatusPhasesEnum_lyrics,
      _$enrichmentStatusPhasesEnum_trackFields,
      _$enrichmentStatusPhasesEnum_bookFields,
      _$enrichmentStatusPhasesEnum_albumFields,
      _$enrichmentStatusPhasesEnum_unknownDefaultOpenApi,
    ]);

Serializer<EnrichmentStatusPhasesEnum> _$enrichmentStatusPhasesEnumSerializer =
    _$EnrichmentStatusPhasesEnumSerializer();

class _$EnrichmentStatusPhasesEnumSerializer
    implements PrimitiveSerializer<EnrichmentStatusPhasesEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'identity': 'identity',
    'releases': 'releases',
    'auxArt': 'aux-art',
    'artistArt': 'artist-art',
    'lyrics': 'lyrics',
    'trackFields': 'track-fields',
    'bookFields': 'book-fields',
    'albumFields': 'album-fields',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'identity': 'identity',
    'releases': 'releases',
    'aux-art': 'auxArt',
    'artist-art': 'artistArt',
    'lyrics': 'lyrics',
    'track-fields': 'trackFields',
    'book-fields': 'bookFields',
    'album-fields': 'albumFields',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[EnrichmentStatusPhasesEnum];
  @override
  final String wireName = 'EnrichmentStatusPhasesEnum';

  @override
  Object serialize(
    Serializers serializers,
    EnrichmentStatusPhasesEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  EnrichmentStatusPhasesEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => EnrichmentStatusPhasesEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

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
  final bool musicbrainzConfigured;
  @override
  final BuiltList<EnrichmentStatusPhasesEnum> phases;
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
    required this.musicbrainzConfigured,
    required this.phases,
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
        musicbrainzConfigured == other.musicbrainzConfigured &&
        phases == other.phases &&
        lastRun == other.lastRun;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, providers.hashCode);
    _$hash = $jc(_$hash, coverage.hashCode);
    _$hash = $jc(_$hash, running.hashCode);
    _$hash = $jc(_$hash, configured.hashCode);
    _$hash = $jc(_$hash, musicbrainzConfigured.hashCode);
    _$hash = $jc(_$hash, phases.hashCode);
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
          ..add('musicbrainzConfigured', musicbrainzConfigured)
          ..add('phases', phases)
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

  bool? _musicbrainzConfigured;
  bool? get musicbrainzConfigured => _$this._musicbrainzConfigured;
  set musicbrainzConfigured(bool? musicbrainzConfigured) =>
      _$this._musicbrainzConfigured = musicbrainzConfigured;

  ListBuilder<EnrichmentStatusPhasesEnum>? _phases;
  ListBuilder<EnrichmentStatusPhasesEnum> get phases =>
      _$this._phases ??= ListBuilder<EnrichmentStatusPhasesEnum>();
  set phases(ListBuilder<EnrichmentStatusPhasesEnum>? phases) =>
      _$this._phases = phases;

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
      _musicbrainzConfigured = $v.musicbrainzConfigured;
      _phases = $v.phases.toBuilder();
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
            musicbrainzConfigured: BuiltValueNullFieldError.checkNotNull(
              musicbrainzConfigured,
              r'EnrichmentStatus',
              'musicbrainzConfigured',
            ),
            phases: phases.build(),
            lastRun: _lastRun?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'providers';
        providers.build();
        _$failedField = 'coverage';
        coverage.build();

        _$failedField = 'phases';
        phases.build();
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
