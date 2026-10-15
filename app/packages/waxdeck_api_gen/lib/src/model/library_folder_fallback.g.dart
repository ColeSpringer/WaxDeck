// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_folder_fallback.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LibraryFolderFallback extends LibraryFolderFallback {
  @override
  final bool folderFallback;
  @override
  final String? libraryPid;

  factory _$LibraryFolderFallback([
    void Function(LibraryFolderFallbackBuilder)? updates,
  ]) => (LibraryFolderFallbackBuilder()..update(updates))._build();

  _$LibraryFolderFallback._({required this.folderFallback, this.libraryPid})
    : super._();
  @override
  LibraryFolderFallback rebuild(
    void Function(LibraryFolderFallbackBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  LibraryFolderFallbackBuilder toBuilder() =>
      LibraryFolderFallbackBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LibraryFolderFallback &&
        folderFallback == other.folderFallback &&
        libraryPid == other.libraryPid;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, folderFallback.hashCode);
    _$hash = $jc(_$hash, libraryPid.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LibraryFolderFallback')
          ..add('folderFallback', folderFallback)
          ..add('libraryPid', libraryPid))
        .toString();
  }
}

class LibraryFolderFallbackBuilder
    implements Builder<LibraryFolderFallback, LibraryFolderFallbackBuilder> {
  _$LibraryFolderFallback? _$v;

  bool? _folderFallback;
  bool? get folderFallback => _$this._folderFallback;
  set folderFallback(bool? folderFallback) =>
      _$this._folderFallback = folderFallback;

  String? _libraryPid;
  String? get libraryPid => _$this._libraryPid;
  set libraryPid(String? libraryPid) => _$this._libraryPid = libraryPid;

  LibraryFolderFallbackBuilder() {
    LibraryFolderFallback._defaults(this);
  }

  LibraryFolderFallbackBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _folderFallback = $v.folderFallback;
      _libraryPid = $v.libraryPid;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LibraryFolderFallback other) {
    _$v = other as _$LibraryFolderFallback;
  }

  @override
  void update(void Function(LibraryFolderFallbackBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LibraryFolderFallback build() => _build();

  _$LibraryFolderFallback _build() {
    final _$result =
        _$v ??
        _$LibraryFolderFallback._(
          folderFallback: BuiltValueNullFieldError.checkNotNull(
            folderFallback,
            r'LibraryFolderFallback',
            'folderFallback',
          ),
          libraryPid: libraryPid,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
