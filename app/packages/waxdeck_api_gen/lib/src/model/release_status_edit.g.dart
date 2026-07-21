// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'release_status_edit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ReleaseStatusEdit extends ReleaseStatusEdit {
  @override
  final bool unofficial;

  factory _$ReleaseStatusEdit([
    void Function(ReleaseStatusEditBuilder)? updates,
  ]) => (ReleaseStatusEditBuilder()..update(updates))._build();

  _$ReleaseStatusEdit._({required this.unofficial}) : super._();
  @override
  ReleaseStatusEdit rebuild(void Function(ReleaseStatusEditBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ReleaseStatusEditBuilder toBuilder() =>
      ReleaseStatusEditBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReleaseStatusEdit && unofficial == other.unofficial;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, unofficial.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'ReleaseStatusEdit',
    )..add('unofficial', unofficial)).toString();
  }
}

class ReleaseStatusEditBuilder
    implements Builder<ReleaseStatusEdit, ReleaseStatusEditBuilder> {
  _$ReleaseStatusEdit? _$v;

  bool? _unofficial;
  bool? get unofficial => _$this._unofficial;
  set unofficial(bool? unofficial) => _$this._unofficial = unofficial;

  ReleaseStatusEditBuilder() {
    ReleaseStatusEdit._defaults(this);
  }

  ReleaseStatusEditBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _unofficial = $v.unofficial;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReleaseStatusEdit other) {
    _$v = other as _$ReleaseStatusEdit;
  }

  @override
  void update(void Function(ReleaseStatusEditBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReleaseStatusEdit build() => _build();

  _$ReleaseStatusEdit _build() {
    final _$result =
        _$v ??
        _$ReleaseStatusEdit._(
          unofficial: BuiltValueNullFieldError.checkNotNull(
            unofficial,
            r'ReleaseStatusEdit',
            'unofficial',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
