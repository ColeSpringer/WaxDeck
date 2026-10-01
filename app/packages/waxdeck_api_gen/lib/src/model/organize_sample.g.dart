// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'organize_sample.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OrganizeSample extends OrganizeSample {
  @override
  final String music;
  @override
  final String audiobook;
  @override
  final String podcast;

  factory _$OrganizeSample([void Function(OrganizeSampleBuilder)? updates]) =>
      (OrganizeSampleBuilder()..update(updates))._build();

  _$OrganizeSample._({
    required this.music,
    required this.audiobook,
    required this.podcast,
  }) : super._();
  @override
  OrganizeSample rebuild(void Function(OrganizeSampleBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OrganizeSampleBuilder toBuilder() => OrganizeSampleBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OrganizeSample &&
        music == other.music &&
        audiobook == other.audiobook &&
        podcast == other.podcast;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, music.hashCode);
    _$hash = $jc(_$hash, audiobook.hashCode);
    _$hash = $jc(_$hash, podcast.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OrganizeSample')
          ..add('music', music)
          ..add('audiobook', audiobook)
          ..add('podcast', podcast))
        .toString();
  }
}

class OrganizeSampleBuilder
    implements Builder<OrganizeSample, OrganizeSampleBuilder> {
  _$OrganizeSample? _$v;

  String? _music;
  String? get music => _$this._music;
  set music(String? music) => _$this._music = music;

  String? _audiobook;
  String? get audiobook => _$this._audiobook;
  set audiobook(String? audiobook) => _$this._audiobook = audiobook;

  String? _podcast;
  String? get podcast => _$this._podcast;
  set podcast(String? podcast) => _$this._podcast = podcast;

  OrganizeSampleBuilder() {
    OrganizeSample._defaults(this);
  }

  OrganizeSampleBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _music = $v.music;
      _audiobook = $v.audiobook;
      _podcast = $v.podcast;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OrganizeSample other) {
    _$v = other as _$OrganizeSample;
  }

  @override
  void update(void Function(OrganizeSampleBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OrganizeSample build() => _build();

  _$OrganizeSample _build() {
    final _$result =
        _$v ??
        _$OrganizeSample._(
          music: BuiltValueNullFieldError.checkNotNull(
            music,
            r'OrganizeSample',
            'music',
          ),
          audiobook: BuiltValueNullFieldError.checkNotNull(
            audiobook,
            r'OrganizeSample',
            'audiobook',
          ),
          podcast: BuiltValueNullFieldError.checkNotNull(
            podcast,
            r'OrganizeSample',
            'podcast',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
