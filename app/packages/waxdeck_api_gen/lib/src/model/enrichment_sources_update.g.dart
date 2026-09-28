// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrichment_sources_update.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichmentSourcesUpdate extends EnrichmentSourcesUpdate {
  @override
  final BuiltList<EnrichmentSource> sources;

  factory _$EnrichmentSourcesUpdate([
    void Function(EnrichmentSourcesUpdateBuilder)? updates,
  ]) => (EnrichmentSourcesUpdateBuilder()..update(updates))._build();

  _$EnrichmentSourcesUpdate._({required this.sources}) : super._();
  @override
  EnrichmentSourcesUpdate rebuild(
    void Function(EnrichmentSourcesUpdateBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  EnrichmentSourcesUpdateBuilder toBuilder() =>
      EnrichmentSourcesUpdateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichmentSourcesUpdate && sources == other.sources;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, sources.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'EnrichmentSourcesUpdate',
    )..add('sources', sources)).toString();
  }
}

class EnrichmentSourcesUpdateBuilder
    implements
        Builder<EnrichmentSourcesUpdate, EnrichmentSourcesUpdateBuilder> {
  _$EnrichmentSourcesUpdate? _$v;

  ListBuilder<EnrichmentSource>? _sources;
  ListBuilder<EnrichmentSource> get sources =>
      _$this._sources ??= ListBuilder<EnrichmentSource>();
  set sources(ListBuilder<EnrichmentSource>? sources) =>
      _$this._sources = sources;

  EnrichmentSourcesUpdateBuilder() {
    EnrichmentSourcesUpdate._defaults(this);
  }

  EnrichmentSourcesUpdateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sources = $v.sources.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichmentSourcesUpdate other) {
    _$v = other as _$EnrichmentSourcesUpdate;
  }

  @override
  void update(void Function(EnrichmentSourcesUpdateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichmentSourcesUpdate build() => _build();

  _$EnrichmentSourcesUpdate _build() {
    _$EnrichmentSourcesUpdate _$result;
    try {
      _$result = _$v ?? _$EnrichmentSourcesUpdate._(sources: sources.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'sources';
        sources.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EnrichmentSourcesUpdate',
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
