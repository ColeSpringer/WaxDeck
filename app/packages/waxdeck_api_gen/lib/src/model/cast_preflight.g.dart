// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cast_preflight.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CastPreflight extends CastPreflight {
  @override
  final BuiltList<CastPreflightBase> bases;

  factory _$CastPreflight([void Function(CastPreflightBuilder)? updates]) =>
      (CastPreflightBuilder()..update(updates))._build();

  _$CastPreflight._({required this.bases}) : super._();
  @override
  CastPreflight rebuild(void Function(CastPreflightBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CastPreflightBuilder toBuilder() => CastPreflightBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CastPreflight && bases == other.bases;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, bases.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'CastPreflight',
    )..add('bases', bases)).toString();
  }
}

class CastPreflightBuilder
    implements Builder<CastPreflight, CastPreflightBuilder> {
  _$CastPreflight? _$v;

  ListBuilder<CastPreflightBase>? _bases;
  ListBuilder<CastPreflightBase> get bases =>
      _$this._bases ??= ListBuilder<CastPreflightBase>();
  set bases(ListBuilder<CastPreflightBase>? bases) => _$this._bases = bases;

  CastPreflightBuilder() {
    CastPreflight._defaults(this);
  }

  CastPreflightBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _bases = $v.bases.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CastPreflight other) {
    _$v = other as _$CastPreflight;
  }

  @override
  void update(void Function(CastPreflightBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CastPreflight build() => _build();

  _$CastPreflight _build() {
    _$CastPreflight _$result;
    try {
      _$result = _$v ?? _$CastPreflight._(bases: bases.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'bases';
        bases.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'CastPreflight',
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
