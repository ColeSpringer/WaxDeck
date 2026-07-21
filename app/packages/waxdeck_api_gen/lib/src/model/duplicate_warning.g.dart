// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'duplicate_warning.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DuplicateWarning extends DuplicateWarning {
  @override
  final String itemPid;
  @override
  final String kind;
  @override
  final String? title;
  @override
  final String? artist;

  factory _$DuplicateWarning([
    void Function(DuplicateWarningBuilder)? updates,
  ]) => (DuplicateWarningBuilder()..update(updates))._build();

  _$DuplicateWarning._({
    required this.itemPid,
    required this.kind,
    this.title,
    this.artist,
  }) : super._();
  @override
  DuplicateWarning rebuild(void Function(DuplicateWarningBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DuplicateWarningBuilder toBuilder() =>
      DuplicateWarningBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DuplicateWarning &&
        itemPid == other.itemPid &&
        kind == other.kind &&
        title == other.title &&
        artist == other.artist;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, itemPid.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, artist.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DuplicateWarning')
          ..add('itemPid', itemPid)
          ..add('kind', kind)
          ..add('title', title)
          ..add('artist', artist))
        .toString();
  }
}

class DuplicateWarningBuilder
    implements Builder<DuplicateWarning, DuplicateWarningBuilder> {
  _$DuplicateWarning? _$v;

  String? _itemPid;
  String? get itemPid => _$this._itemPid;
  set itemPid(String? itemPid) => _$this._itemPid = itemPid;

  String? _kind;
  String? get kind => _$this._kind;
  set kind(String? kind) => _$this._kind = kind;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _artist;
  String? get artist => _$this._artist;
  set artist(String? artist) => _$this._artist = artist;

  DuplicateWarningBuilder() {
    DuplicateWarning._defaults(this);
  }

  DuplicateWarningBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _itemPid = $v.itemPid;
      _kind = $v.kind;
      _title = $v.title;
      _artist = $v.artist;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DuplicateWarning other) {
    _$v = other as _$DuplicateWarning;
  }

  @override
  void update(void Function(DuplicateWarningBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DuplicateWarning build() => _build();

  _$DuplicateWarning _build() {
    final _$result =
        _$v ??
        _$DuplicateWarning._(
          itemPid: BuiltValueNullFieldError.checkNotNull(
            itemPid,
            r'DuplicateWarning',
            'itemPid',
          ),
          kind: BuiltValueNullFieldError.checkNotNull(
            kind,
            r'DuplicateWarning',
            'kind',
          ),
          title: title,
          artist: artist,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
