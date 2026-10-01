// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_created.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LibraryCreated extends LibraryCreated {
  @override
  final bool? scanStarted;
  @override
  final String? streamingWarning;
  @override
  final String pid;
  @override
  final String name;
  @override
  final String? media;
  @override
  final String? path;
  @override
  final int? itemCount;
  @override
  final bool readOnly;
  @override
  final bool managed;
  @override
  final String? profile;

  factory _$LibraryCreated([void Function(LibraryCreatedBuilder)? updates]) =>
      (LibraryCreatedBuilder()..update(updates))._build();

  _$LibraryCreated._({
    this.scanStarted,
    this.streamingWarning,
    required this.pid,
    required this.name,
    this.media,
    this.path,
    this.itemCount,
    required this.readOnly,
    required this.managed,
    this.profile,
  }) : super._();
  @override
  LibraryCreated rebuild(void Function(LibraryCreatedBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LibraryCreatedBuilder toBuilder() => LibraryCreatedBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LibraryCreated &&
        scanStarted == other.scanStarted &&
        streamingWarning == other.streamingWarning &&
        pid == other.pid &&
        name == other.name &&
        media == other.media &&
        path == other.path &&
        itemCount == other.itemCount &&
        readOnly == other.readOnly &&
        managed == other.managed &&
        profile == other.profile;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, scanStarted.hashCode);
    _$hash = $jc(_$hash, streamingWarning.hashCode);
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, media.hashCode);
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, itemCount.hashCode);
    _$hash = $jc(_$hash, readOnly.hashCode);
    _$hash = $jc(_$hash, managed.hashCode);
    _$hash = $jc(_$hash, profile.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LibraryCreated')
          ..add('scanStarted', scanStarted)
          ..add('streamingWarning', streamingWarning)
          ..add('pid', pid)
          ..add('name', name)
          ..add('media', media)
          ..add('path', path)
          ..add('itemCount', itemCount)
          ..add('readOnly', readOnly)
          ..add('managed', managed)
          ..add('profile', profile))
        .toString();
  }
}

class LibraryCreatedBuilder
    implements
        Builder<LibraryCreated, LibraryCreatedBuilder>,
        ModelLibraryBuilder {
  _$LibraryCreated? _$v;

  bool? _scanStarted;
  bool? get scanStarted => _$this._scanStarted;
  set scanStarted(covariant bool? scanStarted) =>
      _$this._scanStarted = scanStarted;

  String? _streamingWarning;
  String? get streamingWarning => _$this._streamingWarning;
  set streamingWarning(covariant String? streamingWarning) =>
      _$this._streamingWarning = streamingWarning;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(covariant String? pid) => _$this._pid = pid;

  String? _name;
  String? get name => _$this._name;
  set name(covariant String? name) => _$this._name = name;

  String? _media;
  String? get media => _$this._media;
  set media(covariant String? media) => _$this._media = media;

  String? _path;
  String? get path => _$this._path;
  set path(covariant String? path) => _$this._path = path;

  int? _itemCount;
  int? get itemCount => _$this._itemCount;
  set itemCount(covariant int? itemCount) => _$this._itemCount = itemCount;

  bool? _readOnly;
  bool? get readOnly => _$this._readOnly;
  set readOnly(covariant bool? readOnly) => _$this._readOnly = readOnly;

  bool? _managed;
  bool? get managed => _$this._managed;
  set managed(covariant bool? managed) => _$this._managed = managed;

  String? _profile;
  String? get profile => _$this._profile;
  set profile(covariant String? profile) => _$this._profile = profile;

  LibraryCreatedBuilder() {
    LibraryCreated._defaults(this);
  }

  LibraryCreatedBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _scanStarted = $v.scanStarted;
      _streamingWarning = $v.streamingWarning;
      _pid = $v.pid;
      _name = $v.name;
      _media = $v.media;
      _path = $v.path;
      _itemCount = $v.itemCount;
      _readOnly = $v.readOnly;
      _managed = $v.managed;
      _profile = $v.profile;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant LibraryCreated other) {
    _$v = other as _$LibraryCreated;
  }

  @override
  void update(void Function(LibraryCreatedBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LibraryCreated build() => _build();

  _$LibraryCreated _build() {
    final _$result =
        _$v ??
        _$LibraryCreated._(
          scanStarted: scanStarted,
          streamingWarning: streamingWarning,
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'LibraryCreated',
            'pid',
          ),
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'LibraryCreated',
            'name',
          ),
          media: media,
          path: path,
          itemCount: itemCount,
          readOnly: BuiltValueNullFieldError.checkNotNull(
            readOnly,
            r'LibraryCreated',
            'readOnly',
          ),
          managed: BuiltValueNullFieldError.checkNotNull(
            managed,
            r'LibraryCreated',
            'managed',
          ),
          profile: profile,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
