// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'item_file.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ItemFile extends ItemFile {
  @override
  final String filePid;
  @override
  final String role;
  @override
  final String name;
  @override
  final String? path;
  @override
  final int? sizeBytes;
  @override
  final String? codec;
  @override
  final String? container;
  @override
  final int? bitrate;
  @override
  final int? sampleRate;
  @override
  final int? bitDepth;
  @override
  final int? durationMs;
  @override
  final String? libraryPid;
  @override
  final String? reason;

  factory _$ItemFile([void Function(ItemFileBuilder)? updates]) =>
      (ItemFileBuilder()..update(updates))._build();

  _$ItemFile._({
    required this.filePid,
    required this.role,
    required this.name,
    this.path,
    this.sizeBytes,
    this.codec,
    this.container,
    this.bitrate,
    this.sampleRate,
    this.bitDepth,
    this.durationMs,
    this.libraryPid,
    this.reason,
  }) : super._();
  @override
  ItemFile rebuild(void Function(ItemFileBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ItemFileBuilder toBuilder() => ItemFileBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ItemFile &&
        filePid == other.filePid &&
        role == other.role &&
        name == other.name &&
        path == other.path &&
        sizeBytes == other.sizeBytes &&
        codec == other.codec &&
        container == other.container &&
        bitrate == other.bitrate &&
        sampleRate == other.sampleRate &&
        bitDepth == other.bitDepth &&
        durationMs == other.durationMs &&
        libraryPid == other.libraryPid &&
        reason == other.reason;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, filePid.hashCode);
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, sizeBytes.hashCode);
    _$hash = $jc(_$hash, codec.hashCode);
    _$hash = $jc(_$hash, container.hashCode);
    _$hash = $jc(_$hash, bitrate.hashCode);
    _$hash = $jc(_$hash, sampleRate.hashCode);
    _$hash = $jc(_$hash, bitDepth.hashCode);
    _$hash = $jc(_$hash, durationMs.hashCode);
    _$hash = $jc(_$hash, libraryPid.hashCode);
    _$hash = $jc(_$hash, reason.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ItemFile')
          ..add('filePid', filePid)
          ..add('role', role)
          ..add('name', name)
          ..add('path', path)
          ..add('sizeBytes', sizeBytes)
          ..add('codec', codec)
          ..add('container', container)
          ..add('bitrate', bitrate)
          ..add('sampleRate', sampleRate)
          ..add('bitDepth', bitDepth)
          ..add('durationMs', durationMs)
          ..add('libraryPid', libraryPid)
          ..add('reason', reason))
        .toString();
  }
}

class ItemFileBuilder implements Builder<ItemFile, ItemFileBuilder> {
  _$ItemFile? _$v;

  String? _filePid;
  String? get filePid => _$this._filePid;
  set filePid(String? filePid) => _$this._filePid = filePid;

  String? _role;
  String? get role => _$this._role;
  set role(String? role) => _$this._role = role;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  int? _sizeBytes;
  int? get sizeBytes => _$this._sizeBytes;
  set sizeBytes(int? sizeBytes) => _$this._sizeBytes = sizeBytes;

  String? _codec;
  String? get codec => _$this._codec;
  set codec(String? codec) => _$this._codec = codec;

  String? _container;
  String? get container => _$this._container;
  set container(String? container) => _$this._container = container;

  int? _bitrate;
  int? get bitrate => _$this._bitrate;
  set bitrate(int? bitrate) => _$this._bitrate = bitrate;

  int? _sampleRate;
  int? get sampleRate => _$this._sampleRate;
  set sampleRate(int? sampleRate) => _$this._sampleRate = sampleRate;

  int? _bitDepth;
  int? get bitDepth => _$this._bitDepth;
  set bitDepth(int? bitDepth) => _$this._bitDepth = bitDepth;

  int? _durationMs;
  int? get durationMs => _$this._durationMs;
  set durationMs(int? durationMs) => _$this._durationMs = durationMs;

  String? _libraryPid;
  String? get libraryPid => _$this._libraryPid;
  set libraryPid(String? libraryPid) => _$this._libraryPid = libraryPid;

  String? _reason;
  String? get reason => _$this._reason;
  set reason(String? reason) => _$this._reason = reason;

  ItemFileBuilder() {
    ItemFile._defaults(this);
  }

  ItemFileBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _filePid = $v.filePid;
      _role = $v.role;
      _name = $v.name;
      _path = $v.path;
      _sizeBytes = $v.sizeBytes;
      _codec = $v.codec;
      _container = $v.container;
      _bitrate = $v.bitrate;
      _sampleRate = $v.sampleRate;
      _bitDepth = $v.bitDepth;
      _durationMs = $v.durationMs;
      _libraryPid = $v.libraryPid;
      _reason = $v.reason;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ItemFile other) {
    _$v = other as _$ItemFile;
  }

  @override
  void update(void Function(ItemFileBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ItemFile build() => _build();

  _$ItemFile _build() {
    final _$result =
        _$v ??
        _$ItemFile._(
          filePid: BuiltValueNullFieldError.checkNotNull(
            filePid,
            r'ItemFile',
            'filePid',
          ),
          role: BuiltValueNullFieldError.checkNotNull(
            role,
            r'ItemFile',
            'role',
          ),
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'ItemFile',
            'name',
          ),
          path: path,
          sizeBytes: sizeBytes,
          codec: codec,
          container: container,
          bitrate: bitrate,
          sampleRate: sampleRate,
          bitDepth: bitDepth,
          durationMs: durationMs,
          libraryPid: libraryPid,
          reason: reason,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
