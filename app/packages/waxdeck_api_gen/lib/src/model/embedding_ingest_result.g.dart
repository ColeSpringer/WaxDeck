// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'embedding_ingest_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EmbeddingIngestResult extends EmbeddingIngestResult {
  @override
  final int accepted;
  @override
  final int replaced;
  @override
  final BuiltList<RejectedEmbedding>? rejected;

  factory _$EmbeddingIngestResult([
    void Function(EmbeddingIngestResultBuilder)? updates,
  ]) => (EmbeddingIngestResultBuilder()..update(updates))._build();

  _$EmbeddingIngestResult._({
    required this.accepted,
    required this.replaced,
    this.rejected,
  }) : super._();
  @override
  EmbeddingIngestResult rebuild(
    void Function(EmbeddingIngestResultBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  EmbeddingIngestResultBuilder toBuilder() =>
      EmbeddingIngestResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EmbeddingIngestResult &&
        accepted == other.accepted &&
        replaced == other.replaced &&
        rejected == other.rejected;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, accepted.hashCode);
    _$hash = $jc(_$hash, replaced.hashCode);
    _$hash = $jc(_$hash, rejected.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EmbeddingIngestResult')
          ..add('accepted', accepted)
          ..add('replaced', replaced)
          ..add('rejected', rejected))
        .toString();
  }
}

class EmbeddingIngestResultBuilder
    implements Builder<EmbeddingIngestResult, EmbeddingIngestResultBuilder> {
  _$EmbeddingIngestResult? _$v;

  int? _accepted;
  int? get accepted => _$this._accepted;
  set accepted(int? accepted) => _$this._accepted = accepted;

  int? _replaced;
  int? get replaced => _$this._replaced;
  set replaced(int? replaced) => _$this._replaced = replaced;

  ListBuilder<RejectedEmbedding>? _rejected;
  ListBuilder<RejectedEmbedding> get rejected =>
      _$this._rejected ??= ListBuilder<RejectedEmbedding>();
  set rejected(ListBuilder<RejectedEmbedding>? rejected) =>
      _$this._rejected = rejected;

  EmbeddingIngestResultBuilder() {
    EmbeddingIngestResult._defaults(this);
  }

  EmbeddingIngestResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _accepted = $v.accepted;
      _replaced = $v.replaced;
      _rejected = $v.rejected?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EmbeddingIngestResult other) {
    _$v = other as _$EmbeddingIngestResult;
  }

  @override
  void update(void Function(EmbeddingIngestResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EmbeddingIngestResult build() => _build();

  _$EmbeddingIngestResult _build() {
    _$EmbeddingIngestResult _$result;
    try {
      _$result =
          _$v ??
          _$EmbeddingIngestResult._(
            accepted: BuiltValueNullFieldError.checkNotNull(
              accepted,
              r'EmbeddingIngestResult',
              'accepted',
            ),
            replaced: BuiltValueNullFieldError.checkNotNull(
              replaced,
              r'EmbeddingIngestResult',
              'replaced',
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
          r'EmbeddingIngestResult',
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
