// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rematch_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RematchResult extends RematchResult {
  @override
  final String reviewEntryId;

  factory _$RematchResult([void Function(RematchResultBuilder)? updates]) =>
      (RematchResultBuilder()..update(updates))._build();

  _$RematchResult._({required this.reviewEntryId}) : super._();
  @override
  RematchResult rebuild(void Function(RematchResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RematchResultBuilder toBuilder() => RematchResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RematchResult && reviewEntryId == other.reviewEntryId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, reviewEntryId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'RematchResult',
    )..add('reviewEntryId', reviewEntryId)).toString();
  }
}

class RematchResultBuilder
    implements Builder<RematchResult, RematchResultBuilder> {
  _$RematchResult? _$v;

  String? _reviewEntryId;
  String? get reviewEntryId => _$this._reviewEntryId;
  set reviewEntryId(String? reviewEntryId) =>
      _$this._reviewEntryId = reviewEntryId;

  RematchResultBuilder() {
    RematchResult._defaults(this);
  }

  RematchResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _reviewEntryId = $v.reviewEntryId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RematchResult other) {
    _$v = other as _$RematchResult;
  }

  @override
  void update(void Function(RematchResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RematchResult build() => _build();

  _$RematchResult _build() {
    final _$result =
        _$v ??
        _$RematchResult._(
          reviewEntryId: BuiltValueNullFieldError.checkNotNull(
            reviewEntryId,
            r'RematchResult',
            'reviewEntryId',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
