// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'oidc_providers.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OidcProviders extends OidcProviders {
  @override
  final BuiltList<OidcProvider> providers;

  factory _$OidcProviders([void Function(OidcProvidersBuilder)? updates]) =>
      (OidcProvidersBuilder()..update(updates))._build();

  _$OidcProviders._({required this.providers}) : super._();
  @override
  OidcProviders rebuild(void Function(OidcProvidersBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OidcProvidersBuilder toBuilder() => OidcProvidersBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OidcProviders && providers == other.providers;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, providers.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'OidcProviders',
    )..add('providers', providers)).toString();
  }
}

class OidcProvidersBuilder
    implements Builder<OidcProviders, OidcProvidersBuilder> {
  _$OidcProviders? _$v;

  ListBuilder<OidcProvider>? _providers;
  ListBuilder<OidcProvider> get providers =>
      _$this._providers ??= ListBuilder<OidcProvider>();
  set providers(ListBuilder<OidcProvider>? providers) =>
      _$this._providers = providers;

  OidcProvidersBuilder() {
    OidcProviders._defaults(this);
  }

  OidcProvidersBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _providers = $v.providers.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OidcProviders other) {
    _$v = other as _$OidcProviders;
  }

  @override
  void update(void Function(OidcProvidersBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OidcProviders build() => _build();

  _$OidcProviders _build() {
    _$OidcProviders _$result;
    try {
      _$result = _$v ?? _$OidcProviders._(providers: providers.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'providers';
        providers.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'OidcProviders',
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
