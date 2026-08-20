// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'art_role_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ArtRoleInfo extends ArtRoleInfo {
  @override
  final ArtRole role;
  @override
  final String? format;
  @override
  final int? width;
  @override
  final int? height;
  @override
  final String? source_;
  @override
  final String? provider;
  @override
  final String? sourceUrl;
  @override
  final DateTime? updatedAt;
  @override
  final bool? locked;

  factory _$ArtRoleInfo([void Function(ArtRoleInfoBuilder)? updates]) =>
      (ArtRoleInfoBuilder()..update(updates))._build();

  _$ArtRoleInfo._({
    required this.role,
    this.format,
    this.width,
    this.height,
    this.source_,
    this.provider,
    this.sourceUrl,
    this.updatedAt,
    this.locked,
  }) : super._();
  @override
  ArtRoleInfo rebuild(void Function(ArtRoleInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ArtRoleInfoBuilder toBuilder() => ArtRoleInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ArtRoleInfo &&
        role == other.role &&
        format == other.format &&
        width == other.width &&
        height == other.height &&
        source_ == other.source_ &&
        provider == other.provider &&
        sourceUrl == other.sourceUrl &&
        updatedAt == other.updatedAt &&
        locked == other.locked;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jc(_$hash, format.hashCode);
    _$hash = $jc(_$hash, width.hashCode);
    _$hash = $jc(_$hash, height.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, sourceUrl.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, locked.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ArtRoleInfo')
          ..add('role', role)
          ..add('format', format)
          ..add('width', width)
          ..add('height', height)
          ..add('source_', source_)
          ..add('provider', provider)
          ..add('sourceUrl', sourceUrl)
          ..add('updatedAt', updatedAt)
          ..add('locked', locked))
        .toString();
  }
}

class ArtRoleInfoBuilder implements Builder<ArtRoleInfo, ArtRoleInfoBuilder> {
  _$ArtRoleInfo? _$v;

  ArtRole? _role;
  ArtRole? get role => _$this._role;
  set role(ArtRole? role) => _$this._role = role;

  String? _format;
  String? get format => _$this._format;
  set format(String? format) => _$this._format = format;

  int? _width;
  int? get width => _$this._width;
  set width(int? width) => _$this._width = width;

  int? _height;
  int? get height => _$this._height;
  set height(int? height) => _$this._height = height;

  String? _source_;
  String? get source_ => _$this._source_;
  set source_(String? source_) => _$this._source_ = source_;

  String? _provider;
  String? get provider => _$this._provider;
  set provider(String? provider) => _$this._provider = provider;

  String? _sourceUrl;
  String? get sourceUrl => _$this._sourceUrl;
  set sourceUrl(String? sourceUrl) => _$this._sourceUrl = sourceUrl;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  bool? _locked;
  bool? get locked => _$this._locked;
  set locked(bool? locked) => _$this._locked = locked;

  ArtRoleInfoBuilder() {
    ArtRoleInfo._defaults(this);
  }

  ArtRoleInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _role = $v.role;
      _format = $v.format;
      _width = $v.width;
      _height = $v.height;
      _source_ = $v.source_;
      _provider = $v.provider;
      _sourceUrl = $v.sourceUrl;
      _updatedAt = $v.updatedAt;
      _locked = $v.locked;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ArtRoleInfo other) {
    _$v = other as _$ArtRoleInfo;
  }

  @override
  void update(void Function(ArtRoleInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ArtRoleInfo build() => _build();

  _$ArtRoleInfo _build() {
    final _$result =
        _$v ??
        _$ArtRoleInfo._(
          role: BuiltValueNullFieldError.checkNotNull(
            role,
            r'ArtRoleInfo',
            'role',
          ),
          format: format,
          width: width,
          height: height,
          source_: source_,
          provider: provider,
          sourceUrl: sourceUrl,
          updatedAt: updatedAt,
          locked: locked,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
