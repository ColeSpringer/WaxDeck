// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrichment_source.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichmentSource extends EnrichmentSource {
  @override
  final String name;
  @override
  final bool enabled;

  factory _$EnrichmentSource([
    void Function(EnrichmentSourceBuilder)? updates,
  ]) => (EnrichmentSourceBuilder()..update(updates))._build();

  _$EnrichmentSource._({required this.name, required this.enabled}) : super._();
  @override
  EnrichmentSource rebuild(void Function(EnrichmentSourceBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EnrichmentSourceBuilder toBuilder() =>
      EnrichmentSourceBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichmentSource &&
        name == other.name &&
        enabled == other.enabled;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, enabled.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EnrichmentSource')
          ..add('name', name)
          ..add('enabled', enabled))
        .toString();
  }
}

class EnrichmentSourceBuilder
    implements Builder<EnrichmentSource, EnrichmentSourceBuilder> {
  _$EnrichmentSource? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  bool? _enabled;
  bool? get enabled => _$this._enabled;
  set enabled(bool? enabled) => _$this._enabled = enabled;

  EnrichmentSourceBuilder() {
    EnrichmentSource._defaults(this);
  }

  EnrichmentSourceBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _enabled = $v.enabled;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichmentSource other) {
    _$v = other as _$EnrichmentSource;
  }

  @override
  void update(void Function(EnrichmentSourceBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichmentSource build() => _build();

  _$EnrichmentSource _build() {
    final _$result =
        _$v ??
        _$EnrichmentSource._(
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'EnrichmentSource',
            'name',
          ),
          enabled: BuiltValueNullFieldError.checkNotNull(
            enabled,
            r'EnrichmentSource',
            'enabled',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
