// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_profile.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LibraryProfile extends LibraryProfile {
  @override
  final String profile;

  factory _$LibraryProfile([void Function(LibraryProfileBuilder)? updates]) =>
      (LibraryProfileBuilder()..update(updates))._build();

  _$LibraryProfile._({required this.profile}) : super._();
  @override
  LibraryProfile rebuild(void Function(LibraryProfileBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LibraryProfileBuilder toBuilder() => LibraryProfileBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LibraryProfile && profile == other.profile;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, profile.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'LibraryProfile',
    )..add('profile', profile)).toString();
  }
}

class LibraryProfileBuilder
    implements Builder<LibraryProfile, LibraryProfileBuilder> {
  _$LibraryProfile? _$v;

  String? _profile;
  String? get profile => _$this._profile;
  set profile(String? profile) => _$this._profile = profile;

  LibraryProfileBuilder() {
    LibraryProfile._defaults(this);
  }

  LibraryProfileBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _profile = $v.profile;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LibraryProfile other) {
    _$v = other as _$LibraryProfile;
  }

  @override
  void update(void Function(LibraryProfileBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LibraryProfile build() => _build();

  _$LibraryProfile _build() {
    final _$result =
        _$v ??
        _$LibraryProfile._(
          profile: BuiltValueNullFieldError.checkNotNull(
            profile,
            r'LibraryProfile',
            'profile',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
