// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_hit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SearchHit extends SearchHit {
  @override
  final String pid;
  @override
  final String kind;
  @override
  final String title;
  @override
  final String? subtitle;

  factory _$SearchHit([void Function(SearchHitBuilder)? updates]) =>
      (SearchHitBuilder()..update(updates))._build();

  _$SearchHit._({
    required this.pid,
    required this.kind,
    required this.title,
    this.subtitle,
  }) : super._();
  @override
  SearchHit rebuild(void Function(SearchHitBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SearchHitBuilder toBuilder() => SearchHitBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SearchHit &&
        pid == other.pid &&
        kind == other.kind &&
        title == other.title &&
        subtitle == other.subtitle;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, subtitle.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SearchHit')
          ..add('pid', pid)
          ..add('kind', kind)
          ..add('title', title)
          ..add('subtitle', subtitle))
        .toString();
  }
}

class SearchHitBuilder implements Builder<SearchHit, SearchHitBuilder> {
  _$SearchHit? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _kind;
  String? get kind => _$this._kind;
  set kind(String? kind) => _$this._kind = kind;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _subtitle;
  String? get subtitle => _$this._subtitle;
  set subtitle(String? subtitle) => _$this._subtitle = subtitle;

  SearchHitBuilder() {
    SearchHit._defaults(this);
  }

  SearchHitBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _kind = $v.kind;
      _title = $v.title;
      _subtitle = $v.subtitle;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SearchHit other) {
    _$v = other as _$SearchHit;
  }

  @override
  void update(void Function(SearchHitBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SearchHit build() => _build();

  _$SearchHit _build() {
    final _$result =
        _$v ??
        _$SearchHit._(
          pid: BuiltValueNullFieldError.checkNotNull(pid, r'SearchHit', 'pid'),
          kind: BuiltValueNullFieldError.checkNotNull(
            kind,
            r'SearchHit',
            'kind',
          ),
          title: BuiltValueNullFieldError.checkNotNull(
            title,
            r'SearchHit',
            'title',
          ),
          subtitle: subtitle,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
