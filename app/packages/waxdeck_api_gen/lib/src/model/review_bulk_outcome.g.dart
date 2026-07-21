// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_bulk_outcome.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ReviewBulkOutcome extends ReviewBulkOutcome {
  @override
  final String entryId;
  @override
  final bool ok;
  @override
  final String? error;

  factory _$ReviewBulkOutcome([
    void Function(ReviewBulkOutcomeBuilder)? updates,
  ]) => (ReviewBulkOutcomeBuilder()..update(updates))._build();

  _$ReviewBulkOutcome._({required this.entryId, required this.ok, this.error})
    : super._();
  @override
  ReviewBulkOutcome rebuild(void Function(ReviewBulkOutcomeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ReviewBulkOutcomeBuilder toBuilder() =>
      ReviewBulkOutcomeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReviewBulkOutcome &&
        entryId == other.entryId &&
        ok == other.ok &&
        error == other.error;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entryId.hashCode);
    _$hash = $jc(_$hash, ok.hashCode);
    _$hash = $jc(_$hash, error.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReviewBulkOutcome')
          ..add('entryId', entryId)
          ..add('ok', ok)
          ..add('error', error))
        .toString();
  }
}

class ReviewBulkOutcomeBuilder
    implements Builder<ReviewBulkOutcome, ReviewBulkOutcomeBuilder> {
  _$ReviewBulkOutcome? _$v;

  String? _entryId;
  String? get entryId => _$this._entryId;
  set entryId(String? entryId) => _$this._entryId = entryId;

  bool? _ok;
  bool? get ok => _$this._ok;
  set ok(bool? ok) => _$this._ok = ok;

  String? _error;
  String? get error => _$this._error;
  set error(String? error) => _$this._error = error;

  ReviewBulkOutcomeBuilder() {
    ReviewBulkOutcome._defaults(this);
  }

  ReviewBulkOutcomeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entryId = $v.entryId;
      _ok = $v.ok;
      _error = $v.error;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReviewBulkOutcome other) {
    _$v = other as _$ReviewBulkOutcome;
  }

  @override
  void update(void Function(ReviewBulkOutcomeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReviewBulkOutcome build() => _build();

  _$ReviewBulkOutcome _build() {
    final _$result =
        _$v ??
        _$ReviewBulkOutcome._(
          entryId: BuiltValueNullFieldError.checkNotNull(
            entryId,
            r'ReviewBulkOutcome',
            'entryId',
          ),
          ok: BuiltValueNullFieldError.checkNotNull(
            ok,
            r'ReviewBulkOutcome',
            'ok',
          ),
          error: error,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
