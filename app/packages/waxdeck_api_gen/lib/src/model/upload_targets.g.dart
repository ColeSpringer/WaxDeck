// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_targets.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UploadTargets extends UploadTargets {
  @override
  final BuiltList<UploadTarget> targets;

  factory _$UploadTargets([void Function(UploadTargetsBuilder)? updates]) =>
      (UploadTargetsBuilder()..update(updates))._build();

  _$UploadTargets._({required this.targets}) : super._();
  @override
  UploadTargets rebuild(void Function(UploadTargetsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UploadTargetsBuilder toBuilder() => UploadTargetsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UploadTargets && targets == other.targets;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, targets.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'UploadTargets',
    )..add('targets', targets)).toString();
  }
}

class UploadTargetsBuilder
    implements Builder<UploadTargets, UploadTargetsBuilder> {
  _$UploadTargets? _$v;

  ListBuilder<UploadTarget>? _targets;
  ListBuilder<UploadTarget> get targets =>
      _$this._targets ??= ListBuilder<UploadTarget>();
  set targets(ListBuilder<UploadTarget>? targets) => _$this._targets = targets;

  UploadTargetsBuilder() {
    UploadTargets._defaults(this);
  }

  UploadTargetsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _targets = $v.targets.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UploadTargets other) {
    _$v = other as _$UploadTargets;
  }

  @override
  void update(void Function(UploadTargetsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UploadTargets build() => _build();

  _$UploadTargets _build() {
    _$UploadTargets _$result;
    try {
      _$result = _$v ?? _$UploadTargets._(targets: targets.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'targets';
        targets.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'UploadTargets',
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
