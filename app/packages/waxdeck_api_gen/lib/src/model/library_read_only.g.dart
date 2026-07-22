// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_read_only.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LibraryReadOnly extends LibraryReadOnly {
  @override
  final bool readOnly;
  @override
  final String? libraryPid;

  factory _$LibraryReadOnly([void Function(LibraryReadOnlyBuilder)? updates]) =>
      (LibraryReadOnlyBuilder()..update(updates))._build();

  _$LibraryReadOnly._({required this.readOnly, this.libraryPid}) : super._();
  @override
  LibraryReadOnly rebuild(void Function(LibraryReadOnlyBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LibraryReadOnlyBuilder toBuilder() => LibraryReadOnlyBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LibraryReadOnly &&
        readOnly == other.readOnly &&
        libraryPid == other.libraryPid;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, readOnly.hashCode);
    _$hash = $jc(_$hash, libraryPid.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LibraryReadOnly')
          ..add('readOnly', readOnly)
          ..add('libraryPid', libraryPid))
        .toString();
  }
}

class LibraryReadOnlyBuilder
    implements Builder<LibraryReadOnly, LibraryReadOnlyBuilder> {
  _$LibraryReadOnly? _$v;

  bool? _readOnly;
  bool? get readOnly => _$this._readOnly;
  set readOnly(bool? readOnly) => _$this._readOnly = readOnly;

  String? _libraryPid;
  String? get libraryPid => _$this._libraryPid;
  set libraryPid(String? libraryPid) => _$this._libraryPid = libraryPid;

  LibraryReadOnlyBuilder() {
    LibraryReadOnly._defaults(this);
  }

  LibraryReadOnlyBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _readOnly = $v.readOnly;
      _libraryPid = $v.libraryPid;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LibraryReadOnly other) {
    _$v = other as _$LibraryReadOnly;
  }

  @override
  void update(void Function(LibraryReadOnlyBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LibraryReadOnly build() => _build();

  _$LibraryReadOnly _build() {
    final _$result =
        _$v ??
        _$LibraryReadOnly._(
          readOnly: BuiltValueNullFieldError.checkNotNull(
            readOnly,
            r'LibraryReadOnly',
            'readOnly',
          ),
          libraryPid: libraryPid,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
