// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'embedding_report.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EmbeddingReport extends EmbeddingReport {
  @override
  final String model;
  @override
  final int dims;
  @override
  final BuiltList<EmbeddingUpload> embeddings;

  factory _$EmbeddingReport([void Function(EmbeddingReportBuilder)? updates]) =>
      (EmbeddingReportBuilder()..update(updates))._build();

  _$EmbeddingReport._({
    required this.model,
    required this.dims,
    required this.embeddings,
  }) : super._();
  @override
  EmbeddingReport rebuild(void Function(EmbeddingReportBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EmbeddingReportBuilder toBuilder() => EmbeddingReportBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EmbeddingReport &&
        model == other.model &&
        dims == other.dims &&
        embeddings == other.embeddings;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, model.hashCode);
    _$hash = $jc(_$hash, dims.hashCode);
    _$hash = $jc(_$hash, embeddings.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EmbeddingReport')
          ..add('model', model)
          ..add('dims', dims)
          ..add('embeddings', embeddings))
        .toString();
  }
}

class EmbeddingReportBuilder
    implements Builder<EmbeddingReport, EmbeddingReportBuilder> {
  _$EmbeddingReport? _$v;

  String? _model;
  String? get model => _$this._model;
  set model(String? model) => _$this._model = model;

  int? _dims;
  int? get dims => _$this._dims;
  set dims(int? dims) => _$this._dims = dims;

  ListBuilder<EmbeddingUpload>? _embeddings;
  ListBuilder<EmbeddingUpload> get embeddings =>
      _$this._embeddings ??= ListBuilder<EmbeddingUpload>();
  set embeddings(ListBuilder<EmbeddingUpload>? embeddings) =>
      _$this._embeddings = embeddings;

  EmbeddingReportBuilder() {
    EmbeddingReport._defaults(this);
  }

  EmbeddingReportBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _model = $v.model;
      _dims = $v.dims;
      _embeddings = $v.embeddings.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EmbeddingReport other) {
    _$v = other as _$EmbeddingReport;
  }

  @override
  void update(void Function(EmbeddingReportBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EmbeddingReport build() => _build();

  _$EmbeddingReport _build() {
    _$EmbeddingReport _$result;
    try {
      _$result =
          _$v ??
          _$EmbeddingReport._(
            model: BuiltValueNullFieldError.checkNotNull(
              model,
              r'EmbeddingReport',
              'model',
            ),
            dims: BuiltValueNullFieldError.checkNotNull(
              dims,
              r'EmbeddingReport',
              'dims',
            ),
            embeddings: embeddings.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'embeddings';
        embeddings.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EmbeddingReport',
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
