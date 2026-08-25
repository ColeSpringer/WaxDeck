// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Health extends Health {
  @override
  final String status;
  @override
  final String version;
  @override
  final int apiVersion;
  @override
  final BuiltList<String>? uploadFormats;
  @override
  final BuiltList<String>? rejectedFormats;

  factory _$Health([void Function(HealthBuilder)? updates]) =>
      (HealthBuilder()..update(updates))._build();

  _$Health._({
    required this.status,
    required this.version,
    required this.apiVersion,
    this.uploadFormats,
    this.rejectedFormats,
  }) : super._();
  @override
  Health rebuild(void Function(HealthBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HealthBuilder toBuilder() => HealthBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Health &&
        status == other.status &&
        version == other.version &&
        apiVersion == other.apiVersion &&
        uploadFormats == other.uploadFormats &&
        rejectedFormats == other.rejectedFormats;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jc(_$hash, apiVersion.hashCode);
    _$hash = $jc(_$hash, uploadFormats.hashCode);
    _$hash = $jc(_$hash, rejectedFormats.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Health')
          ..add('status', status)
          ..add('version', version)
          ..add('apiVersion', apiVersion)
          ..add('uploadFormats', uploadFormats)
          ..add('rejectedFormats', rejectedFormats))
        .toString();
  }
}

class HealthBuilder implements Builder<Health, HealthBuilder> {
  _$Health? _$v;

  String? _status;
  String? get status => _$this._status;
  set status(String? status) => _$this._status = status;

  String? _version;
  String? get version => _$this._version;
  set version(String? version) => _$this._version = version;

  int? _apiVersion;
  int? get apiVersion => _$this._apiVersion;
  set apiVersion(int? apiVersion) => _$this._apiVersion = apiVersion;

  ListBuilder<String>? _uploadFormats;
  ListBuilder<String> get uploadFormats =>
      _$this._uploadFormats ??= ListBuilder<String>();
  set uploadFormats(ListBuilder<String>? uploadFormats) =>
      _$this._uploadFormats = uploadFormats;

  ListBuilder<String>? _rejectedFormats;
  ListBuilder<String> get rejectedFormats =>
      _$this._rejectedFormats ??= ListBuilder<String>();
  set rejectedFormats(ListBuilder<String>? rejectedFormats) =>
      _$this._rejectedFormats = rejectedFormats;

  HealthBuilder() {
    Health._defaults(this);
  }

  HealthBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _status = $v.status;
      _version = $v.version;
      _apiVersion = $v.apiVersion;
      _uploadFormats = $v.uploadFormats?.toBuilder();
      _rejectedFormats = $v.rejectedFormats?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Health other) {
    _$v = other as _$Health;
  }

  @override
  void update(void Function(HealthBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Health build() => _build();

  _$Health _build() {
    _$Health _$result;
    try {
      _$result =
          _$v ??
          _$Health._(
            status: BuiltValueNullFieldError.checkNotNull(
              status,
              r'Health',
              'status',
            ),
            version: BuiltValueNullFieldError.checkNotNull(
              version,
              r'Health',
              'version',
            ),
            apiVersion: BuiltValueNullFieldError.checkNotNull(
              apiVersion,
              r'Health',
              'apiVersion',
            ),
            uploadFormats: _uploadFormats?.build(),
            rejectedFormats: _rejectedFormats?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'uploadFormats';
        _uploadFormats?.build();
        _$failedField = 'rejectedFormats';
        _rejectedFormats?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'Health',
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
