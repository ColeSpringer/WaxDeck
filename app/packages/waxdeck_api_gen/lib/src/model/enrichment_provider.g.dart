// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrichment_provider.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichmentProvider extends EnrichmentProvider {
  @override
  final String name;
  @override
  final BuiltList<String> capabilities;
  @override
  final bool configured;
  @override
  final bool builtin;

  factory _$EnrichmentProvider([
    void Function(EnrichmentProviderBuilder)? updates,
  ]) => (EnrichmentProviderBuilder()..update(updates))._build();

  _$EnrichmentProvider._({
    required this.name,
    required this.capabilities,
    required this.configured,
    required this.builtin,
  }) : super._();
  @override
  EnrichmentProvider rebuild(
    void Function(EnrichmentProviderBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  EnrichmentProviderBuilder toBuilder() =>
      EnrichmentProviderBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichmentProvider &&
        name == other.name &&
        capabilities == other.capabilities &&
        configured == other.configured &&
        builtin == other.builtin;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, capabilities.hashCode);
    _$hash = $jc(_$hash, configured.hashCode);
    _$hash = $jc(_$hash, builtin.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EnrichmentProvider')
          ..add('name', name)
          ..add('capabilities', capabilities)
          ..add('configured', configured)
          ..add('builtin', builtin))
        .toString();
  }
}

class EnrichmentProviderBuilder
    implements Builder<EnrichmentProvider, EnrichmentProviderBuilder> {
  _$EnrichmentProvider? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  ListBuilder<String>? _capabilities;
  ListBuilder<String> get capabilities =>
      _$this._capabilities ??= ListBuilder<String>();
  set capabilities(ListBuilder<String>? capabilities) =>
      _$this._capabilities = capabilities;

  bool? _configured;
  bool? get configured => _$this._configured;
  set configured(bool? configured) => _$this._configured = configured;

  bool? _builtin;
  bool? get builtin => _$this._builtin;
  set builtin(bool? builtin) => _$this._builtin = builtin;

  EnrichmentProviderBuilder() {
    EnrichmentProvider._defaults(this);
  }

  EnrichmentProviderBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _capabilities = $v.capabilities.toBuilder();
      _configured = $v.configured;
      _builtin = $v.builtin;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichmentProvider other) {
    _$v = other as _$EnrichmentProvider;
  }

  @override
  void update(void Function(EnrichmentProviderBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichmentProvider build() => _build();

  _$EnrichmentProvider _build() {
    _$EnrichmentProvider _$result;
    try {
      _$result =
          _$v ??
          _$EnrichmentProvider._(
            name: BuiltValueNullFieldError.checkNotNull(
              name,
              r'EnrichmentProvider',
              'name',
            ),
            capabilities: capabilities.build(),
            configured: BuiltValueNullFieldError.checkNotNull(
              configured,
              r'EnrichmentProvider',
              'configured',
            ),
            builtin: BuiltValueNullFieldError.checkNotNull(
              builtin,
              r'EnrichmentProvider',
              'builtin',
            ),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'capabilities';
        capabilities.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EnrichmentProvider',
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
