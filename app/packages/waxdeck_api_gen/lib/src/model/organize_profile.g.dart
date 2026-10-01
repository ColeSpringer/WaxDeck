// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'organize_profile.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OrganizeProfile extends OrganizeProfile {
  @override
  final String name;
  @override
  final String musicTemplate;
  @override
  final String audiobookTemplate;
  @override
  final String podcastTemplate;
  @override
  final bool tagWrite;
  @override
  final bool builtIn;
  @override
  final OrganizeSample sample;
  @override
  final OrganizeTemplates? saved;

  factory _$OrganizeProfile([void Function(OrganizeProfileBuilder)? updates]) =>
      (OrganizeProfileBuilder()..update(updates))._build();

  _$OrganizeProfile._({
    required this.name,
    required this.musicTemplate,
    required this.audiobookTemplate,
    required this.podcastTemplate,
    required this.tagWrite,
    required this.builtIn,
    required this.sample,
    this.saved,
  }) : super._();
  @override
  OrganizeProfile rebuild(void Function(OrganizeProfileBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OrganizeProfileBuilder toBuilder() => OrganizeProfileBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OrganizeProfile &&
        name == other.name &&
        musicTemplate == other.musicTemplate &&
        audiobookTemplate == other.audiobookTemplate &&
        podcastTemplate == other.podcastTemplate &&
        tagWrite == other.tagWrite &&
        builtIn == other.builtIn &&
        sample == other.sample &&
        saved == other.saved;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, musicTemplate.hashCode);
    _$hash = $jc(_$hash, audiobookTemplate.hashCode);
    _$hash = $jc(_$hash, podcastTemplate.hashCode);
    _$hash = $jc(_$hash, tagWrite.hashCode);
    _$hash = $jc(_$hash, builtIn.hashCode);
    _$hash = $jc(_$hash, sample.hashCode);
    _$hash = $jc(_$hash, saved.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OrganizeProfile')
          ..add('name', name)
          ..add('musicTemplate', musicTemplate)
          ..add('audiobookTemplate', audiobookTemplate)
          ..add('podcastTemplate', podcastTemplate)
          ..add('tagWrite', tagWrite)
          ..add('builtIn', builtIn)
          ..add('sample', sample)
          ..add('saved', saved))
        .toString();
  }
}

class OrganizeProfileBuilder
    implements Builder<OrganizeProfile, OrganizeProfileBuilder> {
  _$OrganizeProfile? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _musicTemplate;
  String? get musicTemplate => _$this._musicTemplate;
  set musicTemplate(String? musicTemplate) =>
      _$this._musicTemplate = musicTemplate;

  String? _audiobookTemplate;
  String? get audiobookTemplate => _$this._audiobookTemplate;
  set audiobookTemplate(String? audiobookTemplate) =>
      _$this._audiobookTemplate = audiobookTemplate;

  String? _podcastTemplate;
  String? get podcastTemplate => _$this._podcastTemplate;
  set podcastTemplate(String? podcastTemplate) =>
      _$this._podcastTemplate = podcastTemplate;

  bool? _tagWrite;
  bool? get tagWrite => _$this._tagWrite;
  set tagWrite(bool? tagWrite) => _$this._tagWrite = tagWrite;

  bool? _builtIn;
  bool? get builtIn => _$this._builtIn;
  set builtIn(bool? builtIn) => _$this._builtIn = builtIn;

  OrganizeSampleBuilder? _sample;
  OrganizeSampleBuilder get sample =>
      _$this._sample ??= OrganizeSampleBuilder();
  set sample(OrganizeSampleBuilder? sample) => _$this._sample = sample;

  OrganizeTemplatesBuilder? _saved;
  OrganizeTemplatesBuilder get saved =>
      _$this._saved ??= OrganizeTemplatesBuilder();
  set saved(OrganizeTemplatesBuilder? saved) => _$this._saved = saved;

  OrganizeProfileBuilder() {
    OrganizeProfile._defaults(this);
  }

  OrganizeProfileBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _musicTemplate = $v.musicTemplate;
      _audiobookTemplate = $v.audiobookTemplate;
      _podcastTemplate = $v.podcastTemplate;
      _tagWrite = $v.tagWrite;
      _builtIn = $v.builtIn;
      _sample = $v.sample.toBuilder();
      _saved = $v.saved?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OrganizeProfile other) {
    _$v = other as _$OrganizeProfile;
  }

  @override
  void update(void Function(OrganizeProfileBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OrganizeProfile build() => _build();

  _$OrganizeProfile _build() {
    _$OrganizeProfile _$result;
    try {
      _$result =
          _$v ??
          _$OrganizeProfile._(
            name: BuiltValueNullFieldError.checkNotNull(
              name,
              r'OrganizeProfile',
              'name',
            ),
            musicTemplate: BuiltValueNullFieldError.checkNotNull(
              musicTemplate,
              r'OrganizeProfile',
              'musicTemplate',
            ),
            audiobookTemplate: BuiltValueNullFieldError.checkNotNull(
              audiobookTemplate,
              r'OrganizeProfile',
              'audiobookTemplate',
            ),
            podcastTemplate: BuiltValueNullFieldError.checkNotNull(
              podcastTemplate,
              r'OrganizeProfile',
              'podcastTemplate',
            ),
            tagWrite: BuiltValueNullFieldError.checkNotNull(
              tagWrite,
              r'OrganizeProfile',
              'tagWrite',
            ),
            builtIn: BuiltValueNullFieldError.checkNotNull(
              builtIn,
              r'OrganizeProfile',
              'builtIn',
            ),
            sample: sample.build(),
            saved: _saved?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'sample';
        sample.build();
        _$failedField = 'saved';
        _saved?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'OrganizeProfile',
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
