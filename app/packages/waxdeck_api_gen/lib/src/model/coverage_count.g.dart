// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'coverage_count.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CoverageCount extends CoverageCount {
  @override
  final int enriched;
  @override
  final int total;

  factory _$CoverageCount([void Function(CoverageCountBuilder)? updates]) =>
      (CoverageCountBuilder()..update(updates))._build();

  _$CoverageCount._({required this.enriched, required this.total}) : super._();
  @override
  CoverageCount rebuild(void Function(CoverageCountBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CoverageCountBuilder toBuilder() => CoverageCountBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CoverageCount &&
        enriched == other.enriched &&
        total == other.total;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, enriched.hashCode);
    _$hash = $jc(_$hash, total.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CoverageCount')
          ..add('enriched', enriched)
          ..add('total', total))
        .toString();
  }
}

class CoverageCountBuilder
    implements Builder<CoverageCount, CoverageCountBuilder> {
  _$CoverageCount? _$v;

  int? _enriched;
  int? get enriched => _$this._enriched;
  set enriched(int? enriched) => _$this._enriched = enriched;

  int? _total;
  int? get total => _$this._total;
  set total(int? total) => _$this._total = total;

  CoverageCountBuilder() {
    CoverageCount._defaults(this);
  }

  CoverageCountBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _enriched = $v.enriched;
      _total = $v.total;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CoverageCount other) {
    _$v = other as _$CoverageCount;
  }

  @override
  void update(void Function(CoverageCountBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CoverageCount build() => _build();

  _$CoverageCount _build() {
    final _$result =
        _$v ??
        _$CoverageCount._(
          enriched: BuiltValueNullFieldError.checkNotNull(
            enriched,
            r'CoverageCount',
            'enriched',
          ),
          total: BuiltValueNullFieldError.checkNotNull(
            total,
            r'CoverageCount',
            'total',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
