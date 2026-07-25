// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'facet_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FacetPage extends FacetPage {
  @override
  final String dimension;
  @override
  final BuiltList<FacetBucket> buckets;
  @override
  final String? nextCursor;

  factory _$FacetPage([void Function(FacetPageBuilder)? updates]) =>
      (FacetPageBuilder()..update(updates))._build();

  _$FacetPage._({
    required this.dimension,
    required this.buckets,
    this.nextCursor,
  }) : super._();
  @override
  FacetPage rebuild(void Function(FacetPageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FacetPageBuilder toBuilder() => FacetPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FacetPage &&
        dimension == other.dimension &&
        buckets == other.buckets &&
        nextCursor == other.nextCursor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, dimension.hashCode);
    _$hash = $jc(_$hash, buckets.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FacetPage')
          ..add('dimension', dimension)
          ..add('buckets', buckets)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class FacetPageBuilder implements Builder<FacetPage, FacetPageBuilder> {
  _$FacetPage? _$v;

  String? _dimension;
  String? get dimension => _$this._dimension;
  set dimension(String? dimension) => _$this._dimension = dimension;

  ListBuilder<FacetBucket>? _buckets;
  ListBuilder<FacetBucket> get buckets =>
      _$this._buckets ??= ListBuilder<FacetBucket>();
  set buckets(ListBuilder<FacetBucket>? buckets) => _$this._buckets = buckets;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  FacetPageBuilder() {
    FacetPage._defaults(this);
  }

  FacetPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _dimension = $v.dimension;
      _buckets = $v.buckets.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FacetPage other) {
    _$v = other as _$FacetPage;
  }

  @override
  void update(void Function(FacetPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FacetPage build() => _build();

  _$FacetPage _build() {
    _$FacetPage _$result;
    try {
      _$result =
          _$v ??
          _$FacetPage._(
            dimension: BuiltValueNullFieldError.checkNotNull(
              dimension,
              r'FacetPage',
              'dimension',
            ),
            buckets: buckets.build(),
            nextCursor: nextCursor,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'buckets';
        buckets.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'FacetPage',
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
