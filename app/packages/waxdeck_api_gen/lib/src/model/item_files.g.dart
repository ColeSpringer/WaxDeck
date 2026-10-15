// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'item_files.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ItemFiles extends ItemFiles {
  @override
  final BuiltList<ItemFile> files;

  factory _$ItemFiles([void Function(ItemFilesBuilder)? updates]) =>
      (ItemFilesBuilder()..update(updates))._build();

  _$ItemFiles._({required this.files}) : super._();
  @override
  ItemFiles rebuild(void Function(ItemFilesBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ItemFilesBuilder toBuilder() => ItemFilesBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ItemFiles && files == other.files;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, files.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'ItemFiles',
    )..add('files', files)).toString();
  }
}

class ItemFilesBuilder implements Builder<ItemFiles, ItemFilesBuilder> {
  _$ItemFiles? _$v;

  ListBuilder<ItemFile>? _files;
  ListBuilder<ItemFile> get files => _$this._files ??= ListBuilder<ItemFile>();
  set files(ListBuilder<ItemFile>? files) => _$this._files = files;

  ItemFilesBuilder() {
    ItemFiles._defaults(this);
  }

  ItemFilesBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _files = $v.files.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ItemFiles other) {
    _$v = other as _$ItemFiles;
  }

  @override
  void update(void Function(ItemFilesBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ItemFiles build() => _build();

  _$ItemFiles _build() {
    _$ItemFiles _$result;
    try {
      _$result = _$v ?? _$ItemFiles._(files: files.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'files';
        files.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ItemFiles',
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
