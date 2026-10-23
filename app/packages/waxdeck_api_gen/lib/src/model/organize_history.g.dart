// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'organize_history.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OrganizeHistory extends OrganizeHistory {
  @override
  final BuiltList<OrganizeBatch> batches;
  @override
  final String? nextCursor;

  factory _$OrganizeHistory([void Function(OrganizeHistoryBuilder)? updates]) =>
      (OrganizeHistoryBuilder()..update(updates))._build();

  _$OrganizeHistory._({required this.batches, this.nextCursor}) : super._();
  @override
  OrganizeHistory rebuild(void Function(OrganizeHistoryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OrganizeHistoryBuilder toBuilder() => OrganizeHistoryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OrganizeHistory &&
        batches == other.batches &&
        nextCursor == other.nextCursor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, batches.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OrganizeHistory')
          ..add('batches', batches)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class OrganizeHistoryBuilder
    implements Builder<OrganizeHistory, OrganizeHistoryBuilder> {
  _$OrganizeHistory? _$v;

  ListBuilder<OrganizeBatch>? _batches;
  ListBuilder<OrganizeBatch> get batches =>
      _$this._batches ??= ListBuilder<OrganizeBatch>();
  set batches(ListBuilder<OrganizeBatch>? batches) => _$this._batches = batches;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  OrganizeHistoryBuilder() {
    OrganizeHistory._defaults(this);
  }

  OrganizeHistoryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _batches = $v.batches.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OrganizeHistory other) {
    _$v = other as _$OrganizeHistory;
  }

  @override
  void update(void Function(OrganizeHistoryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OrganizeHistory build() => _build();

  _$OrganizeHistory _build() {
    _$OrganizeHistory _$result;
    try {
      _$result =
          _$v ??
          _$OrganizeHistory._(batches: batches.build(), nextCursor: nextCursor);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'batches';
        batches.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'OrganizeHistory',
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
