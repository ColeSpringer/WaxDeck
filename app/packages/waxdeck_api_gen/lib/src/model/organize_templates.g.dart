// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'organize_templates.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OrganizeTemplates extends OrganizeTemplates {
  @override
  final String musicTemplate;
  @override
  final String audiobookTemplate;
  @override
  final String podcastTemplate;

  factory _$OrganizeTemplates([
    void Function(OrganizeTemplatesBuilder)? updates,
  ]) => (OrganizeTemplatesBuilder()..update(updates))._build();

  _$OrganizeTemplates._({
    required this.musicTemplate,
    required this.audiobookTemplate,
    required this.podcastTemplate,
  }) : super._();
  @override
  OrganizeTemplates rebuild(void Function(OrganizeTemplatesBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OrganizeTemplatesBuilder toBuilder() =>
      OrganizeTemplatesBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OrganizeTemplates &&
        musicTemplate == other.musicTemplate &&
        audiobookTemplate == other.audiobookTemplate &&
        podcastTemplate == other.podcastTemplate;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, musicTemplate.hashCode);
    _$hash = $jc(_$hash, audiobookTemplate.hashCode);
    _$hash = $jc(_$hash, podcastTemplate.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OrganizeTemplates')
          ..add('musicTemplate', musicTemplate)
          ..add('audiobookTemplate', audiobookTemplate)
          ..add('podcastTemplate', podcastTemplate))
        .toString();
  }
}

class OrganizeTemplatesBuilder
    implements Builder<OrganizeTemplates, OrganizeTemplatesBuilder> {
  _$OrganizeTemplates? _$v;

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

  OrganizeTemplatesBuilder() {
    OrganizeTemplates._defaults(this);
  }

  OrganizeTemplatesBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _musicTemplate = $v.musicTemplate;
      _audiobookTemplate = $v.audiobookTemplate;
      _podcastTemplate = $v.podcastTemplate;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OrganizeTemplates other) {
    _$v = other as _$OrganizeTemplates;
  }

  @override
  void update(void Function(OrganizeTemplatesBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OrganizeTemplates build() => _build();

  _$OrganizeTemplates _build() {
    final _$result =
        _$v ??
        _$OrganizeTemplates._(
          musicTemplate: BuiltValueNullFieldError.checkNotNull(
            musicTemplate,
            r'OrganizeTemplates',
            'musicTemplate',
          ),
          audiobookTemplate: BuiltValueNullFieldError.checkNotNull(
            audiobookTemplate,
            r'OrganizeTemplates',
            'audiobookTemplate',
          ),
          podcastTemplate: BuiltValueNullFieldError.checkNotNull(
            podcastTemplate,
            r'OrganizeTemplates',
            'podcastTemplate',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
