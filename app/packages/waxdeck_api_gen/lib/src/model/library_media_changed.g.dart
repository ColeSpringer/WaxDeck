// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_media_changed.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LibraryMediaChanged extends LibraryMediaChanged {
  @override
  final bool scanStarted;
  @override
  final String pid;
  @override
  final String name;
  @override
  final String? media;
  @override
  final bool? mediaDeclared;
  @override
  final String? path;
  @override
  final int? itemCount;
  @override
  final bool readOnly;
  @override
  final bool? folderFallback;
  @override
  final bool managed;
  @override
  final String? profile;

  factory _$LibraryMediaChanged([
    void Function(LibraryMediaChangedBuilder)? updates,
  ]) => (LibraryMediaChangedBuilder()..update(updates))._build();

  _$LibraryMediaChanged._({
    required this.scanStarted,
    required this.pid,
    required this.name,
    this.media,
    this.mediaDeclared,
    this.path,
    this.itemCount,
    required this.readOnly,
    this.folderFallback,
    required this.managed,
    this.profile,
  }) : super._();
  @override
  LibraryMediaChanged rebuild(
    void Function(LibraryMediaChangedBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  LibraryMediaChangedBuilder toBuilder() =>
      LibraryMediaChangedBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LibraryMediaChanged &&
        scanStarted == other.scanStarted &&
        pid == other.pid &&
        name == other.name &&
        media == other.media &&
        mediaDeclared == other.mediaDeclared &&
        path == other.path &&
        itemCount == other.itemCount &&
        readOnly == other.readOnly &&
        folderFallback == other.folderFallback &&
        managed == other.managed &&
        profile == other.profile;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, scanStarted.hashCode);
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, media.hashCode);
    _$hash = $jc(_$hash, mediaDeclared.hashCode);
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, itemCount.hashCode);
    _$hash = $jc(_$hash, readOnly.hashCode);
    _$hash = $jc(_$hash, folderFallback.hashCode);
    _$hash = $jc(_$hash, managed.hashCode);
    _$hash = $jc(_$hash, profile.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LibraryMediaChanged')
          ..add('scanStarted', scanStarted)
          ..add('pid', pid)
          ..add('name', name)
          ..add('media', media)
          ..add('mediaDeclared', mediaDeclared)
          ..add('path', path)
          ..add('itemCount', itemCount)
          ..add('readOnly', readOnly)
          ..add('folderFallback', folderFallback)
          ..add('managed', managed)
          ..add('profile', profile))
        .toString();
  }
}

class LibraryMediaChangedBuilder
    implements
        Builder<LibraryMediaChanged, LibraryMediaChangedBuilder>,
        ModelLibraryBuilder {
  _$LibraryMediaChanged? _$v;

  bool? _scanStarted;
  bool? get scanStarted => _$this._scanStarted;
  set scanStarted(covariant bool? scanStarted) =>
      _$this._scanStarted = scanStarted;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(covariant String? pid) => _$this._pid = pid;

  String? _name;
  String? get name => _$this._name;
  set name(covariant String? name) => _$this._name = name;

  String? _media;
  String? get media => _$this._media;
  set media(covariant String? media) => _$this._media = media;

  bool? _mediaDeclared;
  bool? get mediaDeclared => _$this._mediaDeclared;
  set mediaDeclared(covariant bool? mediaDeclared) =>
      _$this._mediaDeclared = mediaDeclared;

  String? _path;
  String? get path => _$this._path;
  set path(covariant String? path) => _$this._path = path;

  int? _itemCount;
  int? get itemCount => _$this._itemCount;
  set itemCount(covariant int? itemCount) => _$this._itemCount = itemCount;

  bool? _readOnly;
  bool? get readOnly => _$this._readOnly;
  set readOnly(covariant bool? readOnly) => _$this._readOnly = readOnly;

  bool? _folderFallback;
  bool? get folderFallback => _$this._folderFallback;
  set folderFallback(covariant bool? folderFallback) =>
      _$this._folderFallback = folderFallback;

  bool? _managed;
  bool? get managed => _$this._managed;
  set managed(covariant bool? managed) => _$this._managed = managed;

  String? _profile;
  String? get profile => _$this._profile;
  set profile(covariant String? profile) => _$this._profile = profile;

  LibraryMediaChangedBuilder() {
    LibraryMediaChanged._defaults(this);
  }

  LibraryMediaChangedBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _scanStarted = $v.scanStarted;
      _pid = $v.pid;
      _name = $v.name;
      _media = $v.media;
      _mediaDeclared = $v.mediaDeclared;
      _path = $v.path;
      _itemCount = $v.itemCount;
      _readOnly = $v.readOnly;
      _folderFallback = $v.folderFallback;
      _managed = $v.managed;
      _profile = $v.profile;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant LibraryMediaChanged other) {
    _$v = other as _$LibraryMediaChanged;
  }

  @override
  void update(void Function(LibraryMediaChangedBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LibraryMediaChanged build() => _build();

  _$LibraryMediaChanged _build() {
    final _$result =
        _$v ??
        _$LibraryMediaChanged._(
          scanStarted: BuiltValueNullFieldError.checkNotNull(
            scanStarted,
            r'LibraryMediaChanged',
            'scanStarted',
          ),
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'LibraryMediaChanged',
            'pid',
          ),
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'LibraryMediaChanged',
            'name',
          ),
          media: media,
          mediaDeclared: mediaDeclared,
          path: path,
          itemCount: itemCount,
          readOnly: BuiltValueNullFieldError.checkNotNull(
            readOnly,
            r'LibraryMediaChanged',
            'readOnly',
          ),
          folderFallback: folderFallback,
          managed: BuiltValueNullFieldError.checkNotNull(
            managed,
            r'LibraryMediaChanged',
            'managed',
          ),
          profile: profile,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
