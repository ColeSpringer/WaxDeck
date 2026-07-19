// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'radio_station.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RadioStation extends RadioStation {
  @override
  final String pid;
  @override
  final String name;
  @override
  final String streamUrl;
  @override
  final String? homepageUrl;
  @override
  final String? logoUrl;
  @override
  final DateTime createdAt;

  factory _$RadioStation([void Function(RadioStationBuilder)? updates]) =>
      (RadioStationBuilder()..update(updates))._build();

  _$RadioStation._({
    required this.pid,
    required this.name,
    required this.streamUrl,
    this.homepageUrl,
    this.logoUrl,
    required this.createdAt,
  }) : super._();
  @override
  RadioStation rebuild(void Function(RadioStationBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RadioStationBuilder toBuilder() => RadioStationBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RadioStation &&
        pid == other.pid &&
        name == other.name &&
        streamUrl == other.streamUrl &&
        homepageUrl == other.homepageUrl &&
        logoUrl == other.logoUrl &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, streamUrl.hashCode);
    _$hash = $jc(_$hash, homepageUrl.hashCode);
    _$hash = $jc(_$hash, logoUrl.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RadioStation')
          ..add('pid', pid)
          ..add('name', name)
          ..add('streamUrl', streamUrl)
          ..add('homepageUrl', homepageUrl)
          ..add('logoUrl', logoUrl)
          ..add('createdAt', createdAt))
        .toString();
  }
}

class RadioStationBuilder
    implements Builder<RadioStation, RadioStationBuilder> {
  _$RadioStation? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

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

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  RadioStationBuilder() {
    RadioStation._defaults(this);
  }

  RadioStationBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _name = $v.name;
      _streamUrl = $v.streamUrl;
      _homepageUrl = $v.homepageUrl;
      _logoUrl = $v.logoUrl;
      _createdAt = $v.createdAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RadioStation other) {
    _$v = other as _$RadioStation;
  }

  @override
  void update(void Function(RadioStationBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RadioStation build() => _build();

  _$RadioStation _build() {
    final _$result =
        _$v ??
        _$RadioStation._(
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'RadioStation',
            'pid',
          ),
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'RadioStation',
            'name',
          ),
          streamUrl: BuiltValueNullFieldError.checkNotNull(
            streamUrl,
            r'RadioStation',
            'streamUrl',
          ),
          homepageUrl: homepageUrl,
          logoUrl: logoUrl,
          createdAt: BuiltValueNullFieldError.checkNotNull(
            createdAt,
            r'RadioStation',
            'createdAt',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
