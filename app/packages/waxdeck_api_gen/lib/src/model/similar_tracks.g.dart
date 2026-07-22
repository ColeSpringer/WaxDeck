// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'similar_tracks.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SimilarTracks extends SimilarTracks {
  @override
  final MixBasis basis;
  @override
  final BuiltList<ItemSummary> items;

  factory _$SimilarTracks([void Function(SimilarTracksBuilder)? updates]) =>
      (SimilarTracksBuilder()..update(updates))._build();

  _$SimilarTracks._({required this.basis, required this.items}) : super._();
  @override
  SimilarTracks rebuild(void Function(SimilarTracksBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SimilarTracksBuilder toBuilder() => SimilarTracksBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SimilarTracks &&
        basis == other.basis &&
        items == other.items;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, basis.hashCode);
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SimilarTracks')
          ..add('basis', basis)
          ..add('items', items))
        .toString();
  }
}

class SimilarTracksBuilder
    implements Builder<SimilarTracks, SimilarTracksBuilder> {
  _$SimilarTracks? _$v;

  MixBasis? _basis;
  MixBasis? get basis => _$this._basis;
  set basis(MixBasis? basis) => _$this._basis = basis;

  ListBuilder<ItemSummary>? _items;
  ListBuilder<ItemSummary> get items =>
      _$this._items ??= ListBuilder<ItemSummary>();
  set items(ListBuilder<ItemSummary>? items) => _$this._items = items;

  SimilarTracksBuilder() {
    SimilarTracks._defaults(this);
  }

  SimilarTracksBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _basis = $v.basis;
      _items = $v.items.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SimilarTracks other) {
    _$v = other as _$SimilarTracks;
  }

  @override
  void update(void Function(SimilarTracksBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SimilarTracks build() => _build();

  _$SimilarTracks _build() {
    _$SimilarTracks _$result;
    try {
      _$result =
          _$v ??
          _$SimilarTracks._(
            basis: BuiltValueNullFieldError.checkNotNull(
              basis,
              r'SimilarTracks',
              'basis',
            ),
            items: items.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        items.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'SimilarTracks',
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
