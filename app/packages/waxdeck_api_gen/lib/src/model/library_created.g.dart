// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_created.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LibraryCreated extends LibraryCreated {
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

  factory _$LibraryCreated([void Function(LibraryCreatedBuilder)? updates]) =>
      (LibraryCreatedBuilder()..update(updates))._build();

  _$LibraryCreated._({
    this.streamingWarning,
    required this.pid,
    required this.name,
    this.media,
    this.path,
    this.itemCount,
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
        streamingWarning == other.streamingWarning &&
        pid == other.pid &&
        name == other.name &&
        media == other.media &&
        path == other.path &&
        itemCount == other.itemCount;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, streamingWarning.hashCode);
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, media.hashCode);
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, itemCount.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LibraryCreated')
          ..add('streamingWarning', streamingWarning)
          ..add('pid', pid)
          ..add('name', name)
          ..add('media', media)
          ..add('path', path)
          ..add('itemCount', itemCount))
        .toString();
  }
}

class LibraryCreatedBuilder
    implements
        Builder<LibraryCreated, LibraryCreatedBuilder>,
        ModelLibraryBuilder {
  _$LibraryCreated? _$v;

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

  LibraryCreatedBuilder() {
    LibraryCreated._defaults(this);
  }

  LibraryCreatedBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _streamingWarning = $v.streamingWarning;
      _pid = $v.pid;
      _name = $v.name;
      _media = $v.media;
      _path = $v.path;
      _itemCount = $v.itemCount;
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
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
