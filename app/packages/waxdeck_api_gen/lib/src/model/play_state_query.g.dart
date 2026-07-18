// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'play_state_query.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlayStateQuery extends PlayStateQuery {
  @override
  final BuiltList<String> pids;

  factory _$PlayStateQuery([void Function(PlayStateQueryBuilder)? updates]) =>
      (PlayStateQueryBuilder()..update(updates))._build();

  _$PlayStateQuery._({required this.pids}) : super._();
  @override
  PlayStateQuery rebuild(void Function(PlayStateQueryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlayStateQueryBuilder toBuilder() => PlayStateQueryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlayStateQuery && pids == other.pids;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pids.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'PlayStateQuery',
    )..add('pids', pids)).toString();
  }
}

class PlayStateQueryBuilder
    implements Builder<PlayStateQuery, PlayStateQueryBuilder> {
  _$PlayStateQuery? _$v;

  ListBuilder<String>? _pids;
  ListBuilder<String> get pids => _$this._pids ??= ListBuilder<String>();
  set pids(ListBuilder<String>? pids) => _$this._pids = pids;

  PlayStateQueryBuilder() {
    PlayStateQuery._defaults(this);
  }

  PlayStateQueryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pids = $v.pids.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlayStateQuery other) {
    _$v = other as _$PlayStateQuery;
  }

  @override
  void update(void Function(PlayStateQueryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlayStateQuery build() => _build();

  _$PlayStateQuery _build() {
    _$PlayStateQuery _$result;
    try {
      _$result = _$v ?? _$PlayStateQuery._(pids: pids.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'pids';
        pids.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlayStateQuery',
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
