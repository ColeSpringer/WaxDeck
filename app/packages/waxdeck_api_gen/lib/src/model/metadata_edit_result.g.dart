// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'metadata_edit_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MetadataEditResult extends MetadataEditResult {
  @override
  final bool applied;
  @override
  final BuiltList<WriteBackFailure>? writeBackFailures;
  @override
  final BuiltList<String>? warnings;

  factory _$MetadataEditResult([
    void Function(MetadataEditResultBuilder)? updates,
  ]) => (MetadataEditResultBuilder()..update(updates))._build();

  _$MetadataEditResult._({
    required this.applied,
    this.writeBackFailures,
    this.warnings,
  }) : super._();
  @override
  MetadataEditResult rebuild(
    void Function(MetadataEditResultBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  MetadataEditResultBuilder toBuilder() =>
      MetadataEditResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MetadataEditResult &&
        applied == other.applied &&
        writeBackFailures == other.writeBackFailures &&
        warnings == other.warnings;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, applied.hashCode);
    _$hash = $jc(_$hash, writeBackFailures.hashCode);
    _$hash = $jc(_$hash, warnings.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MetadataEditResult')
          ..add('applied', applied)
          ..add('writeBackFailures', writeBackFailures)
          ..add('warnings', warnings))
        .toString();
  }
}

class MetadataEditResultBuilder
    implements Builder<MetadataEditResult, MetadataEditResultBuilder> {
  _$MetadataEditResult? _$v;

  bool? _applied;
  bool? get applied => _$this._applied;
  set applied(bool? applied) => _$this._applied = applied;

  ListBuilder<WriteBackFailure>? _writeBackFailures;
  ListBuilder<WriteBackFailure> get writeBackFailures =>
      _$this._writeBackFailures ??= ListBuilder<WriteBackFailure>();
  set writeBackFailures(ListBuilder<WriteBackFailure>? writeBackFailures) =>
      _$this._writeBackFailures = writeBackFailures;

  ListBuilder<String>? _warnings;
  ListBuilder<String> get warnings =>
      _$this._warnings ??= ListBuilder<String>();
  set warnings(ListBuilder<String>? warnings) => _$this._warnings = warnings;

  MetadataEditResultBuilder() {
    MetadataEditResult._defaults(this);
  }

  MetadataEditResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _applied = $v.applied;
      _writeBackFailures = $v.writeBackFailures?.toBuilder();
      _warnings = $v.warnings?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MetadataEditResult other) {
    _$v = other as _$MetadataEditResult;
  }

  @override
  void update(void Function(MetadataEditResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MetadataEditResult build() => _build();

  _$MetadataEditResult _build() {
    _$MetadataEditResult _$result;
    try {
      _$result =
          _$v ??
          _$MetadataEditResult._(
            applied: BuiltValueNullFieldError.checkNotNull(
              applied,
              r'MetadataEditResult',
              'applied',
            ),
            writeBackFailures: _writeBackFailures?.build(),
            warnings: _warnings?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'writeBackFailures';
        _writeBackFailures?.build();
        _$failedField = 'warnings';
        _warnings?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'MetadataEditResult',
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
