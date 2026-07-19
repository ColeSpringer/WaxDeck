// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'refresh_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RefreshResult extends RefreshResult {
  @override
  final int newEpisodes;

  factory _$RefreshResult([void Function(RefreshResultBuilder)? updates]) =>
      (RefreshResultBuilder()..update(updates))._build();

  _$RefreshResult._({required this.newEpisodes}) : super._();
  @override
  RefreshResult rebuild(void Function(RefreshResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RefreshResultBuilder toBuilder() => RefreshResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RefreshResult && newEpisodes == other.newEpisodes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, newEpisodes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'RefreshResult',
    )..add('newEpisodes', newEpisodes)).toString();
  }
}

class RefreshResultBuilder
    implements Builder<RefreshResult, RefreshResultBuilder> {
  _$RefreshResult? _$v;

  int? _newEpisodes;
  int? get newEpisodes => _$this._newEpisodes;
  set newEpisodes(int? newEpisodes) => _$this._newEpisodes = newEpisodes;

  RefreshResultBuilder() {
    RefreshResult._defaults(this);
  }

  RefreshResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _newEpisodes = $v.newEpisodes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RefreshResult other) {
    _$v = other as _$RefreshResult;
  }

  @override
  void update(void Function(RefreshResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RefreshResult build() => _build();

  _$RefreshResult _build() {
    final _$result =
        _$v ??
        _$RefreshResult._(
          newEpisodes: BuiltValueNullFieldError.checkNotNull(
            newEpisodes,
            r'RefreshResult',
            'newEpisodes',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
