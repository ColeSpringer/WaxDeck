// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'similarity_work_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SimilarityWorkPage extends SimilarityWorkPage {
  @override
  final BuiltList<SimilarityWorkItem> items;
  @override
  final int retryAfterSeconds;

  factory _$SimilarityWorkPage([
    void Function(SimilarityWorkPageBuilder)? updates,
  ]) => (SimilarityWorkPageBuilder()..update(updates))._build();

  _$SimilarityWorkPage._({required this.items, required this.retryAfterSeconds})
    : super._();
  @override
  SimilarityWorkPage rebuild(
    void Function(SimilarityWorkPageBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  SimilarityWorkPageBuilder toBuilder() =>
      SimilarityWorkPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SimilarityWorkPage &&
        items == other.items &&
        retryAfterSeconds == other.retryAfterSeconds;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jc(_$hash, retryAfterSeconds.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SimilarityWorkPage')
          ..add('items', items)
          ..add('retryAfterSeconds', retryAfterSeconds))
        .toString();
  }
}

class SimilarityWorkPageBuilder
    implements Builder<SimilarityWorkPage, SimilarityWorkPageBuilder> {
  _$SimilarityWorkPage? _$v;

  ListBuilder<SimilarityWorkItem>? _items;
  ListBuilder<SimilarityWorkItem> get items =>
      _$this._items ??= ListBuilder<SimilarityWorkItem>();
  set items(ListBuilder<SimilarityWorkItem>? items) => _$this._items = items;

  int? _retryAfterSeconds;
  int? get retryAfterSeconds => _$this._retryAfterSeconds;
  set retryAfterSeconds(int? retryAfterSeconds) =>
      _$this._retryAfterSeconds = retryAfterSeconds;

  SimilarityWorkPageBuilder() {
    SimilarityWorkPage._defaults(this);
  }

  SimilarityWorkPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _items = $v.items.toBuilder();
      _retryAfterSeconds = $v.retryAfterSeconds;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SimilarityWorkPage other) {
    _$v = other as _$SimilarityWorkPage;
  }

  @override
  void update(void Function(SimilarityWorkPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SimilarityWorkPage build() => _build();

  _$SimilarityWorkPage _build() {
    _$SimilarityWorkPage _$result;
    try {
      _$result =
          _$v ??
          _$SimilarityWorkPage._(
            items: items.build(),
            retryAfterSeconds: BuiltValueNullFieldError.checkNotNull(
              retryAfterSeconds,
              r'SimilarityWorkPage',
              'retryAfterSeconds',
            ),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        items.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'SimilarityWorkPage',
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
