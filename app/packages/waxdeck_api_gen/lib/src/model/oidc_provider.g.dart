// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'oidc_provider.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OidcProvider extends OidcProvider {
  @override
  final String id;
  @override
  final String displayName;
  @override
  final String startUrl;

  factory _$OidcProvider([void Function(OidcProviderBuilder)? updates]) =>
      (OidcProviderBuilder()..update(updates))._build();

  _$OidcProvider._({
    required this.id,
    required this.displayName,
    required this.startUrl,
  }) : super._();
  @override
  OidcProvider rebuild(void Function(OidcProviderBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OidcProviderBuilder toBuilder() => OidcProviderBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OidcProvider &&
        id == other.id &&
        displayName == other.displayName &&
        startUrl == other.startUrl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, startUrl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OidcProvider')
          ..add('id', id)
          ..add('displayName', displayName)
          ..add('startUrl', startUrl))
        .toString();
  }
}

class OidcProviderBuilder
    implements Builder<OidcProvider, OidcProviderBuilder> {
  _$OidcProvider? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  String? _startUrl;
  String? get startUrl => _$this._startUrl;
  set startUrl(String? startUrl) => _$this._startUrl = startUrl;

  OidcProviderBuilder() {
    OidcProvider._defaults(this);
  }

  OidcProviderBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _displayName = $v.displayName;
      _startUrl = $v.startUrl;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OidcProvider other) {
    _$v = other as _$OidcProvider;
  }

  @override
  void update(void Function(OidcProviderBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OidcProvider build() => _build();

  _$OidcProvider _build() {
    final _$result =
        _$v ??
        _$OidcProvider._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'OidcProvider', 'id'),
          displayName: BuiltValueNullFieldError.checkNotNull(
            displayName,
            r'OidcProvider',
            'displayName',
          ),
          startUrl: BuiltValueNullFieldError.checkNotNull(
            startUrl,
            r'OidcProvider',
            'startUrl',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
