// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'listen_ingest_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ListenIngestResult extends ListenIngestResult {
  @override
  final int accepted;
  @override
  final int duplicates;
  @override
  final BuiltList<RejectedListen>? rejected;

  factory _$ListenIngestResult([
    void Function(ListenIngestResultBuilder)? updates,
  ]) => (ListenIngestResultBuilder()..update(updates))._build();

  _$ListenIngestResult._({
    required this.accepted,
    required this.duplicates,
    this.rejected,
  }) : super._();
  @override
  ListenIngestResult rebuild(
    void Function(ListenIngestResultBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  ListenIngestResultBuilder toBuilder() =>
      ListenIngestResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ListenIngestResult &&
        accepted == other.accepted &&
        duplicates == other.duplicates &&
        rejected == other.rejected;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, accepted.hashCode);
    _$hash = $jc(_$hash, duplicates.hashCode);
    _$hash = $jc(_$hash, rejected.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ListenIngestResult')
          ..add('accepted', accepted)
          ..add('duplicates', duplicates)
          ..add('rejected', rejected))
        .toString();
  }
}

class ListenIngestResultBuilder
    implements Builder<ListenIngestResult, ListenIngestResultBuilder> {
  _$ListenIngestResult? _$v;

  int? _accepted;
  int? get accepted => _$this._accepted;
  set accepted(int? accepted) => _$this._accepted = accepted;

  int? _duplicates;
  int? get duplicates => _$this._duplicates;
  set duplicates(int? duplicates) => _$this._duplicates = duplicates;

  ListBuilder<RejectedListen>? _rejected;
  ListBuilder<RejectedListen> get rejected =>
      _$this._rejected ??= ListBuilder<RejectedListen>();
  set rejected(ListBuilder<RejectedListen>? rejected) =>
      _$this._rejected = rejected;

  ListenIngestResultBuilder() {
    ListenIngestResult._defaults(this);
  }

  ListenIngestResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _accepted = $v.accepted;
      _duplicates = $v.duplicates;
      _rejected = $v.rejected?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ListenIngestResult other) {
    _$v = other as _$ListenIngestResult;
  }

  @override
  void update(void Function(ListenIngestResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ListenIngestResult build() => _build();

  _$ListenIngestResult _build() {
    _$ListenIngestResult _$result;
    try {
      _$result =
          _$v ??
          _$ListenIngestResult._(
            accepted: BuiltValueNullFieldError.checkNotNull(
              accepted,
              r'ListenIngestResult',
              'accepted',
            ),
            duplicates: BuiltValueNullFieldError.checkNotNull(
              duplicates,
              r'ListenIngestResult',
              'duplicates',
            ),
            rejected: _rejected?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'rejected';
        _rejected?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ListenIngestResult',
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
