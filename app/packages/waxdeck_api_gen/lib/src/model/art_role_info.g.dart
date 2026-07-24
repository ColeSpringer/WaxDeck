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

  factory _$ArtRoleInfo([void Function(ArtRoleInfoBuilder)? updates]) =>
      (ArtRoleInfoBuilder()..update(updates))._build();

  _$ArtRoleInfo._({required this.role, this.format, this.width, this.height})
    : super._();
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
        height == other.height;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jc(_$hash, format.hashCode);
    _$hash = $jc(_$hash, width.hashCode);
    _$hash = $jc(_$hash, height.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ArtRoleInfo')
          ..add('role', role)
          ..add('format', format)
          ..add('width', width)
          ..add('height', height))
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
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
