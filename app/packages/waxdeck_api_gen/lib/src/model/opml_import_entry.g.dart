// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'opml_import_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OpmlImportEntry extends OpmlImportEntry {
  @override
  final String feedUrl;
  @override
  final String? title;
  @override
  final String? pid;
  @override
  final String? error;

  factory _$OpmlImportEntry([void Function(OpmlImportEntryBuilder)? updates]) =>
      (OpmlImportEntryBuilder()..update(updates))._build();

  _$OpmlImportEntry._({required this.feedUrl, this.title, this.pid, this.error})
    : super._();
  @override
  OpmlImportEntry rebuild(void Function(OpmlImportEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OpmlImportEntryBuilder toBuilder() => OpmlImportEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OpmlImportEntry &&
        feedUrl == other.feedUrl &&
        title == other.title &&
        pid == other.pid &&
        error == other.error;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, feedUrl.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, error.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OpmlImportEntry')
          ..add('feedUrl', feedUrl)
          ..add('title', title)
          ..add('pid', pid)
          ..add('error', error))
        .toString();
  }
}

class OpmlImportEntryBuilder
    implements Builder<OpmlImportEntry, OpmlImportEntryBuilder> {
  _$OpmlImportEntry? _$v;

  String? _feedUrl;
  String? get feedUrl => _$this._feedUrl;
  set feedUrl(String? feedUrl) => _$this._feedUrl = feedUrl;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _error;
  String? get error => _$this._error;
  set error(String? error) => _$this._error = error;

  OpmlImportEntryBuilder() {
    OpmlImportEntry._defaults(this);
  }

  OpmlImportEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _feedUrl = $v.feedUrl;
      _title = $v.title;
      _pid = $v.pid;
      _error = $v.error;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OpmlImportEntry other) {
    _$v = other as _$OpmlImportEntry;
  }

  @override
  void update(void Function(OpmlImportEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OpmlImportEntry build() => _build();

  _$OpmlImportEntry _build() {
    final _$result =
        _$v ??
        _$OpmlImportEntry._(
          feedUrl: BuiltValueNullFieldError.checkNotNull(
            feedUrl,
            r'OpmlImportEntry',
            'feedUrl',
          ),
          title: title,
          pid: pid,
          error: error,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
