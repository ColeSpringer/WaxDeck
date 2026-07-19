// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'radio_station_edit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RadioStationEdit extends RadioStationEdit {
  @override
  final String name;
  @override
  final String streamUrl;
  @override
  final String? homepageUrl;
  @override
  final String? logoUrl;

  factory _$RadioStationEdit([
    void Function(RadioStationEditBuilder)? updates,
  ]) => (RadioStationEditBuilder()..update(updates))._build();

  _$RadioStationEdit._({
    required this.name,
    required this.streamUrl,
    this.homepageUrl,
    this.logoUrl,
  }) : super._();
  @override
  RadioStationEdit rebuild(void Function(RadioStationEditBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RadioStationEditBuilder toBuilder() =>
      RadioStationEditBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RadioStationEdit &&
        name == other.name &&
        streamUrl == other.streamUrl &&
        homepageUrl == other.homepageUrl &&
        logoUrl == other.logoUrl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, streamUrl.hashCode);
    _$hash = $jc(_$hash, homepageUrl.hashCode);
    _$hash = $jc(_$hash, logoUrl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RadioStationEdit')
          ..add('name', name)
          ..add('streamUrl', streamUrl)
          ..add('homepageUrl', homepageUrl)
          ..add('logoUrl', logoUrl))
        .toString();
  }
}

class RadioStationEditBuilder
    implements Builder<RadioStationEdit, RadioStationEditBuilder> {
  _$RadioStationEdit? _$v;

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

  RadioStationEditBuilder() {
    RadioStationEdit._defaults(this);
  }

  RadioStationEditBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _streamUrl = $v.streamUrl;
      _homepageUrl = $v.homepageUrl;
      _logoUrl = $v.logoUrl;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RadioStationEdit other) {
    _$v = other as _$RadioStationEdit;
  }

  @override
  void update(void Function(RadioStationEditBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RadioStationEdit build() => _build();

  _$RadioStationEdit _build() {
    final _$result =
        _$v ??
        _$RadioStationEdit._(
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'RadioStationEdit',
            'name',
          ),
          streamUrl: BuiltValueNullFieldError.checkNotNull(
            streamUrl,
            r'RadioStationEdit',
            'streamUrl',
          ),
          homepageUrl: homepageUrl,
          logoUrl: logoUrl,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
