// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_decide_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ReviewDecideResult extends ReviewDecideResult {
  @override
  final ReviewEntry entry;
  @override
  final BuiltList<String>? warnings;

  factory _$ReviewDecideResult([
    void Function(ReviewDecideResultBuilder)? updates,
  ]) => (ReviewDecideResultBuilder()..update(updates))._build();

  _$ReviewDecideResult._({required this.entry, this.warnings}) : super._();
  @override
  ReviewDecideResult rebuild(
    void Function(ReviewDecideResultBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  ReviewDecideResultBuilder toBuilder() =>
      ReviewDecideResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReviewDecideResult &&
        entry == other.entry &&
        warnings == other.warnings;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entry.hashCode);
    _$hash = $jc(_$hash, warnings.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReviewDecideResult')
          ..add('entry', entry)
          ..add('warnings', warnings))
        .toString();
  }
}

class ReviewDecideResultBuilder
    implements Builder<ReviewDecideResult, ReviewDecideResultBuilder> {
  _$ReviewDecideResult? _$v;

  ReviewEntry? _entry;
  ReviewEntry? get entry => _$this._entry;
  set entry(ReviewEntry? entry) => _$this._entry = entry;

  ListBuilder<String>? _warnings;
  ListBuilder<String> get warnings =>
      _$this._warnings ??= ListBuilder<String>();
  set warnings(ListBuilder<String>? warnings) => _$this._warnings = warnings;

  ReviewDecideResultBuilder() {
    ReviewDecideResult._defaults(this);
  }

  ReviewDecideResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entry = $v.entry;
      _warnings = $v.warnings?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReviewDecideResult other) {
    _$v = other as _$ReviewDecideResult;
  }

  @override
  void update(void Function(ReviewDecideResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReviewDecideResult build() => _build();

  _$ReviewDecideResult _build() {
    _$ReviewDecideResult _$result;
    try {
      _$result =
          _$v ??
          _$ReviewDecideResult._(
            entry: BuiltValueNullFieldError.checkNotNull(
              entry,
              r'ReviewDecideResult',
              'entry',
            ),
            warnings: _warnings?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'warnings';
        _warnings?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ReviewDecideResult',
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
