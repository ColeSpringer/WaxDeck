// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'embedding_upload.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EmbeddingUpload extends EmbeddingUpload {
  @override
  final String pid;
  @override
  final String essence;
  @override
  final BuiltList<num> vector;

  factory _$EmbeddingUpload([void Function(EmbeddingUploadBuilder)? updates]) =>
      (EmbeddingUploadBuilder()..update(updates))._build();

  _$EmbeddingUpload._({
    required this.pid,
    required this.essence,
    required this.vector,
  }) : super._();
  @override
  EmbeddingUpload rebuild(void Function(EmbeddingUploadBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EmbeddingUploadBuilder toBuilder() => EmbeddingUploadBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EmbeddingUpload &&
        pid == other.pid &&
        essence == other.essence &&
        vector == other.vector;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, essence.hashCode);
    _$hash = $jc(_$hash, vector.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EmbeddingUpload')
          ..add('pid', pid)
          ..add('essence', essence)
          ..add('vector', vector))
        .toString();
  }
}

class EmbeddingUploadBuilder
    implements Builder<EmbeddingUpload, EmbeddingUploadBuilder> {
  _$EmbeddingUpload? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _essence;
  String? get essence => _$this._essence;
  set essence(String? essence) => _$this._essence = essence;

  ListBuilder<num>? _vector;
  ListBuilder<num> get vector => _$this._vector ??= ListBuilder<num>();
  set vector(ListBuilder<num>? vector) => _$this._vector = vector;

  EmbeddingUploadBuilder() {
    EmbeddingUpload._defaults(this);
  }

  EmbeddingUploadBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _essence = $v.essence;
      _vector = $v.vector.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EmbeddingUpload other) {
    _$v = other as _$EmbeddingUpload;
  }

  @override
  void update(void Function(EmbeddingUploadBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EmbeddingUpload build() => _build();

  _$EmbeddingUpload _build() {
    _$EmbeddingUpload _$result;
    try {
      _$result =
          _$v ??
          _$EmbeddingUpload._(
            pid: BuiltValueNullFieldError.checkNotNull(
              pid,
              r'EmbeddingUpload',
              'pid',
            ),
            essence: BuiltValueNullFieldError.checkNotNull(
              essence,
              r'EmbeddingUpload',
              'essence',
            ),
            vector: vector.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'vector';
        vector.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EmbeddingUpload',
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
