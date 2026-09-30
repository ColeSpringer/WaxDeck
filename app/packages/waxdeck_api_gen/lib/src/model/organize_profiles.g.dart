// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'organize_profiles.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OrganizeProfiles extends OrganizeProfiles {
  @override
  final BuiltList<OrganizeProfile> profiles;
  @override
  final int managedLibraries;

  factory _$OrganizeProfiles([
    void Function(OrganizeProfilesBuilder)? updates,
  ]) => (OrganizeProfilesBuilder()..update(updates))._build();

  _$OrganizeProfiles._({required this.profiles, required this.managedLibraries})
    : super._();
  @override
  OrganizeProfiles rebuild(void Function(OrganizeProfilesBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OrganizeProfilesBuilder toBuilder() =>
      OrganizeProfilesBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OrganizeProfiles &&
        profiles == other.profiles &&
        managedLibraries == other.managedLibraries;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, profiles.hashCode);
    _$hash = $jc(_$hash, managedLibraries.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OrganizeProfiles')
          ..add('profiles', profiles)
          ..add('managedLibraries', managedLibraries))
        .toString();
  }
}

class OrganizeProfilesBuilder
    implements Builder<OrganizeProfiles, OrganizeProfilesBuilder> {
  _$OrganizeProfiles? _$v;

  ListBuilder<OrganizeProfile>? _profiles;
  ListBuilder<OrganizeProfile> get profiles =>
      _$this._profiles ??= ListBuilder<OrganizeProfile>();
  set profiles(ListBuilder<OrganizeProfile>? profiles) =>
      _$this._profiles = profiles;

  int? _managedLibraries;
  int? get managedLibraries => _$this._managedLibraries;
  set managedLibraries(int? managedLibraries) =>
      _$this._managedLibraries = managedLibraries;

  OrganizeProfilesBuilder() {
    OrganizeProfiles._defaults(this);
  }

  OrganizeProfilesBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _profiles = $v.profiles.toBuilder();
      _managedLibraries = $v.managedLibraries;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OrganizeProfiles other) {
    _$v = other as _$OrganizeProfiles;
  }

  @override
  void update(void Function(OrganizeProfilesBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OrganizeProfiles build() => _build();

  _$OrganizeProfiles _build() {
    _$OrganizeProfiles _$result;
    try {
      _$result =
          _$v ??
          _$OrganizeProfiles._(
            profiles: profiles.build(),
            managedLibraries: BuiltValueNullFieldError.checkNotNull(
              managedLibraries,
              r'OrganizeProfiles',
              'managedLibraries',
            ),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'profiles';
        profiles.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'OrganizeProfiles',
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
