// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'permissions.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Permissions extends Permissions {
  @override
  final bool download;
  @override
  final bool delete;
  @override
  final bool explicitContent;
  @override
  final bool sharedOutputs;
  @override
  final bool managePodcasts;
  @override
  final int? maxTranscodeKbps;
  @override
  final BuiltList<TagRule>? tagAllow;
  @override
  final BuiltList<TagRule>? tagDeny;

  factory _$Permissions([void Function(PermissionsBuilder)? updates]) =>
      (PermissionsBuilder()..update(updates))._build();

  _$Permissions._({
    required this.download,
    required this.delete,
    required this.explicitContent,
    required this.sharedOutputs,
    required this.managePodcasts,
    this.maxTranscodeKbps,
    this.tagAllow,
    this.tagDeny,
  }) : super._();
  @override
  Permissions rebuild(void Function(PermissionsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PermissionsBuilder toBuilder() => PermissionsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Permissions &&
        download == other.download &&
        delete == other.delete &&
        explicitContent == other.explicitContent &&
        sharedOutputs == other.sharedOutputs &&
        managePodcasts == other.managePodcasts &&
        maxTranscodeKbps == other.maxTranscodeKbps &&
        tagAllow == other.tagAllow &&
        tagDeny == other.tagDeny;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, download.hashCode);
    _$hash = $jc(_$hash, delete.hashCode);
    _$hash = $jc(_$hash, explicitContent.hashCode);
    _$hash = $jc(_$hash, sharedOutputs.hashCode);
    _$hash = $jc(_$hash, managePodcasts.hashCode);
    _$hash = $jc(_$hash, maxTranscodeKbps.hashCode);
    _$hash = $jc(_$hash, tagAllow.hashCode);
    _$hash = $jc(_$hash, tagDeny.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Permissions')
          ..add('download', download)
          ..add('delete', delete)
          ..add('explicitContent', explicitContent)
          ..add('sharedOutputs', sharedOutputs)
          ..add('managePodcasts', managePodcasts)
          ..add('maxTranscodeKbps', maxTranscodeKbps)
          ..add('tagAllow', tagAllow)
          ..add('tagDeny', tagDeny))
        .toString();
  }
}

class PermissionsBuilder implements Builder<Permissions, PermissionsBuilder> {
  _$Permissions? _$v;

  bool? _download;
  bool? get download => _$this._download;
  set download(bool? download) => _$this._download = download;

  bool? _delete;
  bool? get delete => _$this._delete;
  set delete(bool? delete) => _$this._delete = delete;

  bool? _explicitContent;
  bool? get explicitContent => _$this._explicitContent;
  set explicitContent(bool? explicitContent) =>
      _$this._explicitContent = explicitContent;

  bool? _sharedOutputs;
  bool? get sharedOutputs => _$this._sharedOutputs;
  set sharedOutputs(bool? sharedOutputs) =>
      _$this._sharedOutputs = sharedOutputs;

  bool? _managePodcasts;
  bool? get managePodcasts => _$this._managePodcasts;
  set managePodcasts(bool? managePodcasts) =>
      _$this._managePodcasts = managePodcasts;

  int? _maxTranscodeKbps;
  int? get maxTranscodeKbps => _$this._maxTranscodeKbps;
  set maxTranscodeKbps(int? maxTranscodeKbps) =>
      _$this._maxTranscodeKbps = maxTranscodeKbps;

  ListBuilder<TagRule>? _tagAllow;
  ListBuilder<TagRule> get tagAllow =>
      _$this._tagAllow ??= ListBuilder<TagRule>();
  set tagAllow(ListBuilder<TagRule>? tagAllow) => _$this._tagAllow = tagAllow;

  ListBuilder<TagRule>? _tagDeny;
  ListBuilder<TagRule> get tagDeny =>
      _$this._tagDeny ??= ListBuilder<TagRule>();
  set tagDeny(ListBuilder<TagRule>? tagDeny) => _$this._tagDeny = tagDeny;

  PermissionsBuilder() {
    Permissions._defaults(this);
  }

  PermissionsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _download = $v.download;
      _delete = $v.delete;
      _explicitContent = $v.explicitContent;
      _sharedOutputs = $v.sharedOutputs;
      _managePodcasts = $v.managePodcasts;
      _maxTranscodeKbps = $v.maxTranscodeKbps;
      _tagAllow = $v.tagAllow?.toBuilder();
      _tagDeny = $v.tagDeny?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Permissions other) {
    _$v = other as _$Permissions;
  }

  @override
  void update(void Function(PermissionsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Permissions build() => _build();

  _$Permissions _build() {
    _$Permissions _$result;
    try {
      _$result =
          _$v ??
          _$Permissions._(
            download: BuiltValueNullFieldError.checkNotNull(
              download,
              r'Permissions',
              'download',
            ),
            delete: BuiltValueNullFieldError.checkNotNull(
              delete,
              r'Permissions',
              'delete',
            ),
            explicitContent: BuiltValueNullFieldError.checkNotNull(
              explicitContent,
              r'Permissions',
              'explicitContent',
            ),
            sharedOutputs: BuiltValueNullFieldError.checkNotNull(
              sharedOutputs,
              r'Permissions',
              'sharedOutputs',
            ),
            managePodcasts: BuiltValueNullFieldError.checkNotNull(
              managePodcasts,
              r'Permissions',
              'managePodcasts',
            ),
            maxTranscodeKbps: maxTranscodeKbps,
            tagAllow: _tagAllow?.build(),
            tagDeny: _tagDeny?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'tagAllow';
        _tagAllow?.build();
        _$failedField = 'tagDeny';
        _tagDeny?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'Permissions',
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
