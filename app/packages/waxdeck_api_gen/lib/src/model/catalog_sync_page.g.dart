// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_sync_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CatalogSyncPage extends CatalogSyncPage {
  @override
  final BuiltList<CatalogSyncEntry> entries;
  @override
  final String? nextCursor;
  @override
  final String nextSince;
  @override
  final bool? more;

  factory _$CatalogSyncPage([void Function(CatalogSyncPageBuilder)? updates]) =>
      (CatalogSyncPageBuilder()..update(updates))._build();

  _$CatalogSyncPage._({
    required this.entries,
    this.nextCursor,
    required this.nextSince,
    this.more,
  }) : super._();
  @override
  CatalogSyncPage rebuild(void Function(CatalogSyncPageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CatalogSyncPageBuilder toBuilder() => CatalogSyncPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CatalogSyncPage &&
        entries == other.entries &&
        nextCursor == other.nextCursor &&
        nextSince == other.nextSince &&
        more == other.more;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entries.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jc(_$hash, nextSince.hashCode);
    _$hash = $jc(_$hash, more.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CatalogSyncPage')
          ..add('entries', entries)
          ..add('nextCursor', nextCursor)
          ..add('nextSince', nextSince)
          ..add('more', more))
        .toString();
  }
}

class CatalogSyncPageBuilder
    implements Builder<CatalogSyncPage, CatalogSyncPageBuilder> {
  _$CatalogSyncPage? _$v;

  ListBuilder<CatalogSyncEntry>? _entries;
  ListBuilder<CatalogSyncEntry> get entries =>
      _$this._entries ??= ListBuilder<CatalogSyncEntry>();
  set entries(ListBuilder<CatalogSyncEntry>? entries) =>
      _$this._entries = entries;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  String? _nextSince;
  String? get nextSince => _$this._nextSince;
  set nextSince(String? nextSince) => _$this._nextSince = nextSince;

  bool? _more;
  bool? get more => _$this._more;
  set more(bool? more) => _$this._more = more;

  CatalogSyncPageBuilder() {
    CatalogSyncPage._defaults(this);
  }

  CatalogSyncPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entries = $v.entries.toBuilder();
      _nextCursor = $v.nextCursor;
      _nextSince = $v.nextSince;
      _more = $v.more;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CatalogSyncPage other) {
    _$v = other as _$CatalogSyncPage;
  }

  @override
  void update(void Function(CatalogSyncPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CatalogSyncPage build() => _build();

  _$CatalogSyncPage _build() {
    _$CatalogSyncPage _$result;
    try {
      _$result =
          _$v ??
          _$CatalogSyncPage._(
            entries: entries.build(),
            nextCursor: nextCursor,
            nextSince: BuiltValueNullFieldError.checkNotNull(
              nextSince,
              r'CatalogSyncPage',
              'nextSince',
            ),
            more: more,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entries';
        entries.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'CatalogSyncPage',
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
