// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'metadata_commit_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MetadataCommitResult extends MetadataCommitResult {
  @override
  final BuiltList<MetadataCommitPart> parts;
  @override
  final BuiltList<WriteBackFailure>? writeBackFailures;
  @override
  final BuiltList<String>? warnings;

  factory _$MetadataCommitResult([
    void Function(MetadataCommitResultBuilder)? updates,
  ]) => (MetadataCommitResultBuilder()..update(updates))._build();

  _$MetadataCommitResult._({
    required this.parts,
    this.writeBackFailures,
    this.warnings,
  }) : super._();
  @override
  MetadataCommitResult rebuild(
    void Function(MetadataCommitResultBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  MetadataCommitResultBuilder toBuilder() =>
      MetadataCommitResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MetadataCommitResult &&
        parts == other.parts &&
        writeBackFailures == other.writeBackFailures &&
        warnings == other.warnings;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, parts.hashCode);
    _$hash = $jc(_$hash, writeBackFailures.hashCode);
    _$hash = $jc(_$hash, warnings.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MetadataCommitResult')
          ..add('parts', parts)
          ..add('writeBackFailures', writeBackFailures)
          ..add('warnings', warnings))
        .toString();
  }
}

class MetadataCommitResultBuilder
    implements Builder<MetadataCommitResult, MetadataCommitResultBuilder> {
  _$MetadataCommitResult? _$v;

  ListBuilder<MetadataCommitPart>? _parts;
  ListBuilder<MetadataCommitPart> get parts =>
      _$this._parts ??= ListBuilder<MetadataCommitPart>();
  set parts(ListBuilder<MetadataCommitPart>? parts) => _$this._parts = parts;

  ListBuilder<WriteBackFailure>? _writeBackFailures;
  ListBuilder<WriteBackFailure> get writeBackFailures =>
      _$this._writeBackFailures ??= ListBuilder<WriteBackFailure>();
  set writeBackFailures(ListBuilder<WriteBackFailure>? writeBackFailures) =>
      _$this._writeBackFailures = writeBackFailures;

  ListBuilder<String>? _warnings;
  ListBuilder<String> get warnings =>
      _$this._warnings ??= ListBuilder<String>();
  set warnings(ListBuilder<String>? warnings) => _$this._warnings = warnings;

  MetadataCommitResultBuilder() {
    MetadataCommitResult._defaults(this);
  }

  MetadataCommitResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _parts = $v.parts.toBuilder();
      _writeBackFailures = $v.writeBackFailures?.toBuilder();
      _warnings = $v.warnings?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MetadataCommitResult other) {
    _$v = other as _$MetadataCommitResult;
  }

  @override
  void update(void Function(MetadataCommitResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MetadataCommitResult build() => _build();

  _$MetadataCommitResult _build() {
    _$MetadataCommitResult _$result;
    try {
      _$result =
          _$v ??
          _$MetadataCommitResult._(
            parts: parts.build(),
            writeBackFailures: _writeBackFailures?.build(),
            warnings: _warnings?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'parts';
        parts.build();
        _$failedField = 'writeBackFailures';
        _writeBackFailures?.build();
        _$failedField = 'warnings';
        _warnings?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'MetadataCommitResult',
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
