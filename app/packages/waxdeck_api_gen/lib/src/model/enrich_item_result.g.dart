// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrich_item_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichItemResult extends EnrichItemResult {
  @override
  final BuiltList<String> applied;
  @override
  final BuiltList<String> skipped;

  factory _$EnrichItemResult([
    void Function(EnrichItemResultBuilder)? updates,
  ]) => (EnrichItemResultBuilder()..update(updates))._build();

  _$EnrichItemResult._({required this.applied, required this.skipped})
    : super._();
  @override
  EnrichItemResult rebuild(void Function(EnrichItemResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EnrichItemResultBuilder toBuilder() =>
      EnrichItemResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichItemResult &&
        applied == other.applied &&
        skipped == other.skipped;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, applied.hashCode);
    _$hash = $jc(_$hash, skipped.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EnrichItemResult')
          ..add('applied', applied)
          ..add('skipped', skipped))
        .toString();
  }
}

class EnrichItemResultBuilder
    implements Builder<EnrichItemResult, EnrichItemResultBuilder> {
  _$EnrichItemResult? _$v;

  ListBuilder<String>? _applied;
  ListBuilder<String> get applied => _$this._applied ??= ListBuilder<String>();
  set applied(ListBuilder<String>? applied) => _$this._applied = applied;

  ListBuilder<String>? _skipped;
  ListBuilder<String> get skipped => _$this._skipped ??= ListBuilder<String>();
  set skipped(ListBuilder<String>? skipped) => _$this._skipped = skipped;

  EnrichItemResultBuilder() {
    EnrichItemResult._defaults(this);
  }

  EnrichItemResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _applied = $v.applied.toBuilder();
      _skipped = $v.skipped.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichItemResult other) {
    _$v = other as _$EnrichItemResult;
  }

  @override
  void update(void Function(EnrichItemResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichItemResult build() => _build();

  _$EnrichItemResult _build() {
    _$EnrichItemResult _$result;
    try {
      _$result =
          _$v ??
          _$EnrichItemResult._(
            applied: applied.build(),
            skipped: skipped.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'applied';
        applied.build();
        _$failedField = 'skipped';
        skipped.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EnrichItemResult',
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
