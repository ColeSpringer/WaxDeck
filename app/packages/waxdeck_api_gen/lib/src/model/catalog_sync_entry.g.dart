// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_sync_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CatalogSyncEntry extends CatalogSyncEntry {
  @override
  final String op;
  @override
  final String pid;
  @override
  final ItemSummary? item;
  @override
  final EpisodeSummary? episode;
  @override
  final PodcastShow? show_;

  factory _$CatalogSyncEntry([
    void Function(CatalogSyncEntryBuilder)? updates,
  ]) => (CatalogSyncEntryBuilder()..update(updates))._build();

  _$CatalogSyncEntry._({
    required this.op,
    required this.pid,
    this.item,
    this.episode,
    this.show_,
  }) : super._();
  @override
  CatalogSyncEntry rebuild(void Function(CatalogSyncEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CatalogSyncEntryBuilder toBuilder() =>
      CatalogSyncEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CatalogSyncEntry &&
        op == other.op &&
        pid == other.pid &&
        item == other.item &&
        episode == other.episode &&
        show_ == other.show_;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, op.hashCode);
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, item.hashCode);
    _$hash = $jc(_$hash, episode.hashCode);
    _$hash = $jc(_$hash, show_.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CatalogSyncEntry')
          ..add('op', op)
          ..add('pid', pid)
          ..add('item', item)
          ..add('episode', episode)
          ..add('show_', show_))
        .toString();
  }
}

class CatalogSyncEntryBuilder
    implements Builder<CatalogSyncEntry, CatalogSyncEntryBuilder> {
  _$CatalogSyncEntry? _$v;

  String? _op;
  String? get op => _$this._op;
  set op(String? op) => _$this._op = op;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  ItemSummary? _item;
  ItemSummary? get item => _$this._item;
  set item(ItemSummary? item) => _$this._item = item;

  EpisodeSummary? _episode;
  EpisodeSummary? get episode => _$this._episode;
  set episode(EpisodeSummary? episode) => _$this._episode = episode;

  PodcastShowBuilder? _show_;
  PodcastShowBuilder get show_ => _$this._show_ ??= PodcastShowBuilder();
  set show_(PodcastShowBuilder? show_) => _$this._show_ = show_;

  CatalogSyncEntryBuilder() {
    CatalogSyncEntry._defaults(this);
  }

  CatalogSyncEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _op = $v.op;
      _pid = $v.pid;
      _item = $v.item;
      _episode = $v.episode;
      _show_ = $v.show_?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CatalogSyncEntry other) {
    _$v = other as _$CatalogSyncEntry;
  }

  @override
  void update(void Function(CatalogSyncEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CatalogSyncEntry build() => _build();

  _$CatalogSyncEntry _build() {
    _$CatalogSyncEntry _$result;
    try {
      _$result =
          _$v ??
          _$CatalogSyncEntry._(
            op: BuiltValueNullFieldError.checkNotNull(
              op,
              r'CatalogSyncEntry',
              'op',
            ),
            pid: BuiltValueNullFieldError.checkNotNull(
              pid,
              r'CatalogSyncEntry',
              'pid',
            ),
            item: item,
            episode: episode,
            show_: _show_?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'show_';
        _show_?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'CatalogSyncEntry',
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
