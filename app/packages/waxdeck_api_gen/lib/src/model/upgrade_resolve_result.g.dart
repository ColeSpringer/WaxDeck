// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upgrade_resolve_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpgradeResolveResult extends UpgradeResolveResult {
  @override
  final int trashed;

  factory _$UpgradeResolveResult([
    void Function(UpgradeResolveResultBuilder)? updates,
  ]) => (UpgradeResolveResultBuilder()..update(updates))._build();

  _$UpgradeResolveResult._({required this.trashed}) : super._();
  @override
  UpgradeResolveResult rebuild(
    void Function(UpgradeResolveResultBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  UpgradeResolveResultBuilder toBuilder() =>
      UpgradeResolveResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpgradeResolveResult && trashed == other.trashed;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, trashed.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'UpgradeResolveResult',
    )..add('trashed', trashed)).toString();
  }
}

class UpgradeResolveResultBuilder
    implements Builder<UpgradeResolveResult, UpgradeResolveResultBuilder> {
  _$UpgradeResolveResult? _$v;

  int? _trashed;
  int? get trashed => _$this._trashed;
  set trashed(int? trashed) => _$this._trashed = trashed;

  UpgradeResolveResultBuilder() {
    UpgradeResolveResult._defaults(this);
  }

  UpgradeResolveResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _trashed = $v.trashed;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpgradeResolveResult other) {
    _$v = other as _$UpgradeResolveResult;
  }

  @override
  void update(void Function(UpgradeResolveResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpgradeResolveResult build() => _build();

  _$UpgradeResolveResult _build() {
    final _$result =
        _$v ??
        _$UpgradeResolveResult._(
          trashed: BuiltValueNullFieldError.checkNotNull(
            trashed,
            r'UpgradeResolveResult',
            'trashed',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
