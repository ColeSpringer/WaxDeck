// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rating_update.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RatingUpdate extends RatingUpdate {
  @override
  final int? rating;

  factory _$RatingUpdate([void Function(RatingUpdateBuilder)? updates]) =>
      (RatingUpdateBuilder()..update(updates))._build();

  _$RatingUpdate._({this.rating}) : super._();
  @override
  RatingUpdate rebuild(void Function(RatingUpdateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RatingUpdateBuilder toBuilder() => RatingUpdateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RatingUpdate && rating == other.rating;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, rating.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'RatingUpdate',
    )..add('rating', rating)).toString();
  }
}

class RatingUpdateBuilder
    implements Builder<RatingUpdate, RatingUpdateBuilder> {
  _$RatingUpdate? _$v;

  int? _rating;
  int? get rating => _$this._rating;
  set rating(int? rating) => _$this._rating = rating;

  RatingUpdateBuilder() {
    RatingUpdate._defaults(this);
  }

  RatingUpdateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _rating = $v.rating;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RatingUpdate other) {
    _$v = other as _$RatingUpdate;
  }

  @override
  void update(void Function(RatingUpdateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RatingUpdate build() => _build();

  _$RatingUpdate _build() {
    final _$result = _$v ?? _$RatingUpdate._(rating: rating);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
