// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'linked_identity.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LinkedIdentity extends LinkedIdentity {
  @override
  final String provider;
  @override
  final String? email;

  factory _$LinkedIdentity([void Function(LinkedIdentityBuilder)? updates]) =>
      (LinkedIdentityBuilder()..update(updates))._build();

  _$LinkedIdentity._({required this.provider, this.email}) : super._();
  @override
  LinkedIdentity rebuild(void Function(LinkedIdentityBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LinkedIdentityBuilder toBuilder() => LinkedIdentityBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LinkedIdentity &&
        provider == other.provider &&
        email == other.email;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LinkedIdentity')
          ..add('provider', provider)
          ..add('email', email))
        .toString();
  }
}

class LinkedIdentityBuilder
    implements Builder<LinkedIdentity, LinkedIdentityBuilder> {
  _$LinkedIdentity? _$v;

  String? _provider;
  String? get provider => _$this._provider;
  set provider(String? provider) => _$this._provider = provider;

  String? _email;
  String? get email => _$this._email;
  set email(String? email) => _$this._email = email;

  LinkedIdentityBuilder() {
    LinkedIdentity._defaults(this);
  }

  LinkedIdentityBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _provider = $v.provider;
      _email = $v.email;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LinkedIdentity other) {
    _$v = other as _$LinkedIdentity;
  }

  @override
  void update(void Function(LinkedIdentityBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LinkedIdentity build() => _build();

  _$LinkedIdentity _build() {
    final _$result =
        _$v ??
        _$LinkedIdentity._(
          provider: BuiltValueNullFieldError.checkNotNull(
            provider,
            r'LinkedIdentity',
            'provider',
          ),
          email: email,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
