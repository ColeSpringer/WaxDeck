// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_library.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ModelLibrary extends ModelLibrary {
  @override
  final String pid;
  @override
  final String name;
  @override
  final String? media;

  factory _$ModelLibrary([void Function(ModelLibraryBuilder)? updates]) =>
      (ModelLibraryBuilder()..update(updates))._build();

  _$ModelLibrary._({required this.pid, required this.name, this.media})
    : super._();
  @override
  ModelLibrary rebuild(void Function(ModelLibraryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ModelLibraryBuilder toBuilder() => ModelLibraryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ModelLibrary &&
        pid == other.pid &&
        name == other.name &&
        media == other.media;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, media.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ModelLibrary')
          ..add('pid', pid)
          ..add('name', name)
          ..add('media', media))
        .toString();
  }
}

class ModelLibraryBuilder
    implements Builder<ModelLibrary, ModelLibraryBuilder> {
  _$ModelLibrary? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _media;
  String? get media => _$this._media;
  set media(String? media) => _$this._media = media;

  ModelLibraryBuilder() {
    ModelLibrary._defaults(this);
  }

  ModelLibraryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _name = $v.name;
      _media = $v.media;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ModelLibrary other) {
    _$v = other as _$ModelLibrary;
  }

  @override
  void update(void Function(ModelLibraryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ModelLibrary build() => _build();

  _$ModelLibrary _build() {
    final _$result =
        _$v ??
        _$ModelLibrary._(
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'ModelLibrary',
            'pid',
          ),
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'ModelLibrary',
            'name',
          ),
          media: media,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
