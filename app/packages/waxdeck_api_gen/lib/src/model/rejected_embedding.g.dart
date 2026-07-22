// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rejected_embedding.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RejectedEmbedding extends RejectedEmbedding {
  @override
  final String? pid;
  @override
  final String? essence;
  @override
  final String code;
  @override
  final String message;

  factory _$RejectedEmbedding([
    void Function(RejectedEmbeddingBuilder)? updates,
  ]) => (RejectedEmbeddingBuilder()..update(updates))._build();

  _$RejectedEmbedding._({
    this.pid,
    this.essence,
    required this.code,
    required this.message,
  }) : super._();
  @override
  RejectedEmbedding rebuild(void Function(RejectedEmbeddingBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RejectedEmbeddingBuilder toBuilder() =>
      RejectedEmbeddingBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RejectedEmbedding &&
        pid == other.pid &&
        essence == other.essence &&
        code == other.code &&
        message == other.message;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, essence.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RejectedEmbedding')
          ..add('pid', pid)
          ..add('essence', essence)
          ..add('code', code)
          ..add('message', message))
        .toString();
  }
}

class RejectedEmbeddingBuilder
    implements Builder<RejectedEmbedding, RejectedEmbeddingBuilder> {
  _$RejectedEmbedding? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _essence;
  String? get essence => _$this._essence;
  set essence(String? essence) => _$this._essence = essence;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  RejectedEmbeddingBuilder() {
    RejectedEmbedding._defaults(this);
  }

  RejectedEmbeddingBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _essence = $v.essence;
      _code = $v.code;
      _message = $v.message;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RejectedEmbedding other) {
    _$v = other as _$RejectedEmbedding;
  }

  @override
  void update(void Function(RejectedEmbeddingBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RejectedEmbedding build() => _build();

  _$RejectedEmbedding _build() {
    final _$result =
        _$v ??
        _$RejectedEmbedding._(
          pid: pid,
          essence: essence,
          code: BuiltValueNullFieldError.checkNotNull(
            code,
            r'RejectedEmbedding',
            'code',
          ),
          message: BuiltValueNullFieldError.checkNotNull(
            message,
            r'RejectedEmbedding',
            'message',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
