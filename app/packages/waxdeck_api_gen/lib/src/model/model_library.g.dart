// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_library.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

abstract mixin class ModelLibraryBuilder {
  void replace(ModelLibrary other);
  void update(void Function(ModelLibraryBuilder) updates);
  String? get pid;
  set pid(String? pid);

  String? get name;
  set name(String? name);

  String? get media;
  set media(String? media);

  bool? get mediaDeclared;
  set mediaDeclared(bool? mediaDeclared);

  String? get path;
  set path(String? path);

  int? get itemCount;
  set itemCount(int? itemCount);

  bool? get readOnly;
  set readOnly(bool? readOnly);

  bool? get folderFallback;
  set folderFallback(bool? folderFallback);

  bool? get managed;
  set managed(bool? managed);

  String? get profile;
  set profile(String? profile);

  bool? get configured;
  set configured(bool? configured);

  bool? get unreachable;
  set unreachable(bool? unreachable);

  bool? get writable;
  set writable(bool? writable);
}

class _$$ModelLibrary extends $ModelLibrary {
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
  @override
  final bool? configured;
  @override
  final bool? unreachable;
  @override
  final bool? writable;

  factory _$$ModelLibrary([void Function($ModelLibraryBuilder)? updates]) =>
      ($ModelLibraryBuilder()..update(updates))._build();

  _$$ModelLibrary._({
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
    this.configured,
    this.unreachable,
    this.writable,
  }) : super._();
  @override
  $ModelLibrary rebuild(void Function($ModelLibraryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  $ModelLibraryBuilder toBuilder() => $ModelLibraryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is $ModelLibrary &&
        pid == other.pid &&
        name == other.name &&
        media == other.media &&
        mediaDeclared == other.mediaDeclared &&
        path == other.path &&
        itemCount == other.itemCount &&
        readOnly == other.readOnly &&
        folderFallback == other.folderFallback &&
        managed == other.managed &&
        profile == other.profile &&
        configured == other.configured &&
        unreachable == other.unreachable &&
        writable == other.writable;
  }

  @override
  int get hashCode {
    var _$hash = 0;
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
    _$hash = $jc(_$hash, configured.hashCode);
    _$hash = $jc(_$hash, unreachable.hashCode);
    _$hash = $jc(_$hash, writable.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'$ModelLibrary')
          ..add('pid', pid)
          ..add('name', name)
          ..add('media', media)
          ..add('mediaDeclared', mediaDeclared)
          ..add('path', path)
          ..add('itemCount', itemCount)
          ..add('readOnly', readOnly)
          ..add('folderFallback', folderFallback)
          ..add('managed', managed)
          ..add('profile', profile)
          ..add('configured', configured)
          ..add('unreachable', unreachable)
          ..add('writable', writable))
        .toString();
  }
}

class $ModelLibraryBuilder
    implements
        Builder<$ModelLibrary, $ModelLibraryBuilder>,
        ModelLibraryBuilder {
  _$$ModelLibrary? _$v;

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

  bool? _configured;
  bool? get configured => _$this._configured;
  set configured(covariant bool? configured) => _$this._configured = configured;

  bool? _unreachable;
  bool? get unreachable => _$this._unreachable;
  set unreachable(covariant bool? unreachable) =>
      _$this._unreachable = unreachable;

  bool? _writable;
  bool? get writable => _$this._writable;
  set writable(covariant bool? writable) => _$this._writable = writable;

  $ModelLibraryBuilder() {
    $ModelLibrary._defaults(this);
  }

  $ModelLibraryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
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
      _configured = $v.configured;
      _unreachable = $v.unreachable;
      _writable = $v.writable;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant $ModelLibrary other) {
    _$v = other as _$$ModelLibrary;
  }

  @override
  void update(void Function($ModelLibraryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  $ModelLibrary build() => _build();

  _$$ModelLibrary _build() {
    final _$result =
        _$v ??
        _$$ModelLibrary._(
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'$ModelLibrary',
            'pid',
          ),
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'$ModelLibrary',
            'name',
          ),
          media: media,
          mediaDeclared: mediaDeclared,
          path: path,
          itemCount: itemCount,
          readOnly: BuiltValueNullFieldError.checkNotNull(
            readOnly,
            r'$ModelLibrary',
            'readOnly',
          ),
          folderFallback: folderFallback,
          managed: BuiltValueNullFieldError.checkNotNull(
            managed,
            r'$ModelLibrary',
            'managed',
          ),
          profile: profile,
          configured: configured,
          unreachable: unreachable,
          writable: writable,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
