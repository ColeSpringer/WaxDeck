// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'write_back_issue.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WriteBackIssue extends WriteBackIssue {
  @override
  final String filePid;
  @override
  final String code;
  @override
  final String? tagKey;
  @override
  final String? detail;

  factory _$WriteBackIssue([void Function(WriteBackIssueBuilder)? updates]) =>
      (WriteBackIssueBuilder()..update(updates))._build();

  _$WriteBackIssue._({
    required this.filePid,
    required this.code,
    this.tagKey,
    this.detail,
  }) : super._();
  @override
  WriteBackIssue rebuild(void Function(WriteBackIssueBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WriteBackIssueBuilder toBuilder() => WriteBackIssueBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WriteBackIssue &&
        filePid == other.filePid &&
        code == other.code &&
        tagKey == other.tagKey &&
        detail == other.detail;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, filePid.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, tagKey.hashCode);
    _$hash = $jc(_$hash, detail.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WriteBackIssue')
          ..add('filePid', filePid)
          ..add('code', code)
          ..add('tagKey', tagKey)
          ..add('detail', detail))
        .toString();
  }
}

class WriteBackIssueBuilder
    implements Builder<WriteBackIssue, WriteBackIssueBuilder> {
  _$WriteBackIssue? _$v;

  String? _filePid;
  String? get filePid => _$this._filePid;
  set filePid(String? filePid) => _$this._filePid = filePid;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _tagKey;
  String? get tagKey => _$this._tagKey;
  set tagKey(String? tagKey) => _$this._tagKey = tagKey;

  String? _detail;
  String? get detail => _$this._detail;
  set detail(String? detail) => _$this._detail = detail;

  WriteBackIssueBuilder() {
    WriteBackIssue._defaults(this);
  }

  WriteBackIssueBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _filePid = $v.filePid;
      _code = $v.code;
      _tagKey = $v.tagKey;
      _detail = $v.detail;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WriteBackIssue other) {
    _$v = other as _$WriteBackIssue;
  }

  @override
  void update(void Function(WriteBackIssueBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WriteBackIssue build() => _build();

  _$WriteBackIssue _build() {
    final _$result =
        _$v ??
        _$WriteBackIssue._(
          filePid: BuiltValueNullFieldError.checkNotNull(
            filePid,
            r'WriteBackIssue',
            'filePid',
          ),
          code: BuiltValueNullFieldError.checkNotNull(
            code,
            r'WriteBackIssue',
            'code',
          ),
          tagKey: tagKey,
          detail: detail,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
