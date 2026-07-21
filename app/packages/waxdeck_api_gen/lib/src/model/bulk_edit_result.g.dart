// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bulk_edit_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BulkEditResult extends BulkEditResult {
  @override
  final BuiltList<String> edited;
  @override
  final BuiltList<String> skipped;
  @override
  final BuiltList<WriteBackFailure>? writeBackFailures;

  factory _$BulkEditResult([void Function(BulkEditResultBuilder)? updates]) =>
      (BulkEditResultBuilder()..update(updates))._build();

  _$BulkEditResult._({
    required this.edited,
    required this.skipped,
    this.writeBackFailures,
  }) : super._();
  @override
  BulkEditResult rebuild(void Function(BulkEditResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BulkEditResultBuilder toBuilder() => BulkEditResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BulkEditResult &&
        edited == other.edited &&
        skipped == other.skipped &&
        writeBackFailures == other.writeBackFailures;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, edited.hashCode);
    _$hash = $jc(_$hash, skipped.hashCode);
    _$hash = $jc(_$hash, writeBackFailures.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BulkEditResult')
          ..add('edited', edited)
          ..add('skipped', skipped)
          ..add('writeBackFailures', writeBackFailures))
        .toString();
  }
}

class BulkEditResultBuilder
    implements Builder<BulkEditResult, BulkEditResultBuilder> {
  _$BulkEditResult? _$v;

  ListBuilder<String>? _edited;
  ListBuilder<String> get edited => _$this._edited ??= ListBuilder<String>();
  set edited(ListBuilder<String>? edited) => _$this._edited = edited;

  ListBuilder<String>? _skipped;
  ListBuilder<String> get skipped => _$this._skipped ??= ListBuilder<String>();
  set skipped(ListBuilder<String>? skipped) => _$this._skipped = skipped;

  ListBuilder<WriteBackFailure>? _writeBackFailures;
  ListBuilder<WriteBackFailure> get writeBackFailures =>
      _$this._writeBackFailures ??= ListBuilder<WriteBackFailure>();
  set writeBackFailures(ListBuilder<WriteBackFailure>? writeBackFailures) =>
      _$this._writeBackFailures = writeBackFailures;

  BulkEditResultBuilder() {
    BulkEditResult._defaults(this);
  }

  BulkEditResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _edited = $v.edited.toBuilder();
      _skipped = $v.skipped.toBuilder();
      _writeBackFailures = $v.writeBackFailures?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BulkEditResult other) {
    _$v = other as _$BulkEditResult;
  }

  @override
  void update(void Function(BulkEditResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BulkEditResult build() => _build();

  _$BulkEditResult _build() {
    _$BulkEditResult _$result;
    try {
      _$result =
          _$v ??
          _$BulkEditResult._(
            edited: edited.build(),
            skipped: skipped.build(),
            writeBackFailures: _writeBackFailures?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'edited';
        edited.build();
        _$failedField = 'skipped';
        skipped.build();
        _$failedField = 'writeBackFailures';
        _writeBackFailures?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'BulkEditResult',
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
