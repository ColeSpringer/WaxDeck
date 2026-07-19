// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'radio_directory_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RadioDirectoryEntry extends RadioDirectoryEntry {
  @override
  final String name;
  @override
  final String streamUrl;
  @override
  final String? homepageUrl;
  @override
  final String? logoUrl;
  @override
  final String? tags;
  @override
  final String? country;
  @override
  final String? codec;
  @override
  final int? bitrateKbps;

  factory _$RadioDirectoryEntry([
    void Function(RadioDirectoryEntryBuilder)? updates,
  ]) => (RadioDirectoryEntryBuilder()..update(updates))._build();

  _$RadioDirectoryEntry._({
    required this.name,
    required this.streamUrl,
    this.homepageUrl,
    this.logoUrl,
    this.tags,
    this.country,
    this.codec,
    this.bitrateKbps,
  }) : super._();
  @override
  RadioDirectoryEntry rebuild(
    void Function(RadioDirectoryEntryBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  RadioDirectoryEntryBuilder toBuilder() =>
      RadioDirectoryEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RadioDirectoryEntry &&
        name == other.name &&
        streamUrl == other.streamUrl &&
        homepageUrl == other.homepageUrl &&
        logoUrl == other.logoUrl &&
        tags == other.tags &&
        country == other.country &&
        codec == other.codec &&
        bitrateKbps == other.bitrateKbps;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, streamUrl.hashCode);
    _$hash = $jc(_$hash, homepageUrl.hashCode);
    _$hash = $jc(_$hash, logoUrl.hashCode);
    _$hash = $jc(_$hash, tags.hashCode);
    _$hash = $jc(_$hash, country.hashCode);
    _$hash = $jc(_$hash, codec.hashCode);
    _$hash = $jc(_$hash, bitrateKbps.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RadioDirectoryEntry')
          ..add('name', name)
          ..add('streamUrl', streamUrl)
          ..add('homepageUrl', homepageUrl)
          ..add('logoUrl', logoUrl)
          ..add('tags', tags)
          ..add('country', country)
          ..add('codec', codec)
          ..add('bitrateKbps', bitrateKbps))
        .toString();
  }
}

class RadioDirectoryEntryBuilder
    implements Builder<RadioDirectoryEntry, RadioDirectoryEntryBuilder> {
  _$RadioDirectoryEntry? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _streamUrl;
  String? get streamUrl => _$this._streamUrl;
  set streamUrl(String? streamUrl) => _$this._streamUrl = streamUrl;

  String? _homepageUrl;
  String? get homepageUrl => _$this._homepageUrl;
  set homepageUrl(String? homepageUrl) => _$this._homepageUrl = homepageUrl;

  String? _logoUrl;
  String? get logoUrl => _$this._logoUrl;
  set logoUrl(String? logoUrl) => _$this._logoUrl = logoUrl;

  String? _tags;
  String? get tags => _$this._tags;
  set tags(String? tags) => _$this._tags = tags;

  String? _country;
  String? get country => _$this._country;
  set country(String? country) => _$this._country = country;

  String? _codec;
  String? get codec => _$this._codec;
  set codec(String? codec) => _$this._codec = codec;

  int? _bitrateKbps;
  int? get bitrateKbps => _$this._bitrateKbps;
  set bitrateKbps(int? bitrateKbps) => _$this._bitrateKbps = bitrateKbps;

  RadioDirectoryEntryBuilder() {
    RadioDirectoryEntry._defaults(this);
  }

  RadioDirectoryEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _streamUrl = $v.streamUrl;
      _homepageUrl = $v.homepageUrl;
      _logoUrl = $v.logoUrl;
      _tags = $v.tags;
      _country = $v.country;
      _codec = $v.codec;
      _bitrateKbps = $v.bitrateKbps;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RadioDirectoryEntry other) {
    _$v = other as _$RadioDirectoryEntry;
  }

  @override
  void update(void Function(RadioDirectoryEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RadioDirectoryEntry build() => _build();

  _$RadioDirectoryEntry _build() {
    final _$result =
        _$v ??
        _$RadioDirectoryEntry._(
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'RadioDirectoryEntry',
            'name',
          ),
          streamUrl: BuiltValueNullFieldError.checkNotNull(
            streamUrl,
            r'RadioDirectoryEntry',
            'streamUrl',
          ),
          homepageUrl: homepageUrl,
          logoUrl: logoUrl,
          tags: tags,
          country: country,
          codec: codec,
          bitrateKbps: bitrateKbps,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
