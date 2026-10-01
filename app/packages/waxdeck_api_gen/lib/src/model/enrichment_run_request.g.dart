// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrichment_run_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichmentRunRequest extends EnrichmentRunRequest {
  @override
  final bool? force;
  @override
  final BuiltList<EnrichmentPhase>? forcePhases;
  @override
  final BuiltList<EnrichmentPhase>? phases;

  factory _$EnrichmentRunRequest([
    void Function(EnrichmentRunRequestBuilder)? updates,
  ]) => (EnrichmentRunRequestBuilder()..update(updates))._build();

  _$EnrichmentRunRequest._({this.force, this.forcePhases, this.phases})
    : super._();
  @override
  EnrichmentRunRequest rebuild(
    void Function(EnrichmentRunRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  EnrichmentRunRequestBuilder toBuilder() =>
      EnrichmentRunRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichmentRunRequest &&
        force == other.force &&
        forcePhases == other.forcePhases &&
        phases == other.phases;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, force.hashCode);
    _$hash = $jc(_$hash, forcePhases.hashCode);
    _$hash = $jc(_$hash, phases.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EnrichmentRunRequest')
          ..add('force', force)
          ..add('forcePhases', forcePhases)
          ..add('phases', phases))
        .toString();
  }
}

class EnrichmentRunRequestBuilder
    implements Builder<EnrichmentRunRequest, EnrichmentRunRequestBuilder> {
  _$EnrichmentRunRequest? _$v;

  bool? _force;
  bool? get force => _$this._force;
  set force(bool? force) => _$this._force = force;

  ListBuilder<EnrichmentPhase>? _forcePhases;
  ListBuilder<EnrichmentPhase> get forcePhases =>
      _$this._forcePhases ??= ListBuilder<EnrichmentPhase>();
  set forcePhases(ListBuilder<EnrichmentPhase>? forcePhases) =>
      _$this._forcePhases = forcePhases;

  ListBuilder<EnrichmentPhase>? _phases;
  ListBuilder<EnrichmentPhase> get phases =>
      _$this._phases ??= ListBuilder<EnrichmentPhase>();
  set phases(ListBuilder<EnrichmentPhase>? phases) => _$this._phases = phases;

  EnrichmentRunRequestBuilder() {
    EnrichmentRunRequest._defaults(this);
  }

  EnrichmentRunRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _force = $v.force;
      _forcePhases = $v.forcePhases?.toBuilder();
      _phases = $v.phases?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichmentRunRequest other) {
    _$v = other as _$EnrichmentRunRequest;
  }

  @override
  void update(void Function(EnrichmentRunRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichmentRunRequest build() => _build();

  _$EnrichmentRunRequest _build() {
    _$EnrichmentRunRequest _$result;
    try {
      _$result =
          _$v ??
          _$EnrichmentRunRequest._(
            force: force,
            forcePhases: _forcePhases?.build(),
            phases: _phases?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'forcePhases';
        _forcePhases?.build();
        _$failedField = 'phases';
        _phases?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EnrichmentRunRequest',
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
