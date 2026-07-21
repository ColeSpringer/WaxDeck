// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'write_back_failure.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WriteBackFailure extends WriteBackFailure {
  @override
  final String filePid;
  @override
  final String? path;
  @override
  final String reason;

  factory _$WriteBackFailure([
    void Function(WriteBackFailureBuilder)? updates,
  ]) => (WriteBackFailureBuilder()..update(updates))._build();

  _$WriteBackFailure._({required this.filePid, this.path, required this.reason})
    : super._();
  @override
  WriteBackFailure rebuild(void Function(WriteBackFailureBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WriteBackFailureBuilder toBuilder() =>
      WriteBackFailureBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WriteBackFailure &&
        filePid == other.filePid &&
        path == other.path &&
        reason == other.reason;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, filePid.hashCode);
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, reason.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WriteBackFailure')
          ..add('filePid', filePid)
          ..add('path', path)
          ..add('reason', reason))
        .toString();
  }
}

class WriteBackFailureBuilder
    implements Builder<WriteBackFailure, WriteBackFailureBuilder> {
  _$WriteBackFailure? _$v;

  String? _filePid;
  String? get filePid => _$this._filePid;
  set filePid(String? filePid) => _$this._filePid = filePid;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  String? _reason;
  String? get reason => _$this._reason;
  set reason(String? reason) => _$this._reason = reason;

  WriteBackFailureBuilder() {
    WriteBackFailure._defaults(this);
  }

  WriteBackFailureBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _filePid = $v.filePid;
      _path = $v.path;
      _reason = $v.reason;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WriteBackFailure other) {
    _$v = other as _$WriteBackFailure;
  }

  @override
  void update(void Function(WriteBackFailureBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WriteBackFailure build() => _build();

  _$WriteBackFailure _build() {
    final _$result =
        _$v ??
        _$WriteBackFailure._(
          filePid: BuiltValueNullFieldError.checkNotNull(
            filePid,
            r'WriteBackFailure',
            'filePid',
          ),
          path: path,
          reason: BuiltValueNullFieldError.checkNotNull(
            reason,
            r'WriteBackFailure',
            'reason',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
