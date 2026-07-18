// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_password_create.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AppPasswordCreate extends AppPasswordCreate {
  @override
  final String label;

  factory _$AppPasswordCreate([
    void Function(AppPasswordCreateBuilder)? updates,
  ]) => (AppPasswordCreateBuilder()..update(updates))._build();

  _$AppPasswordCreate._({required this.label}) : super._();
  @override
  AppPasswordCreate rebuild(void Function(AppPasswordCreateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AppPasswordCreateBuilder toBuilder() =>
      AppPasswordCreateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AppPasswordCreate && label == other.label;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'AppPasswordCreate',
    )..add('label', label)).toString();
  }
}

class AppPasswordCreateBuilder
    implements Builder<AppPasswordCreate, AppPasswordCreateBuilder> {
  _$AppPasswordCreate? _$v;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  AppPasswordCreateBuilder() {
    AppPasswordCreate._defaults(this);
  }

  AppPasswordCreateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _label = $v.label;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AppPasswordCreate other) {
    _$v = other as _$AppPasswordCreate;
  }

  @override
  void update(void Function(AppPasswordCreateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AppPasswordCreate build() => _build();

  _$AppPasswordCreate _build() {
    final _$result =
        _$v ??
        _$AppPasswordCreate._(
          label: BuiltValueNullFieldError.checkNotNull(
            label,
            r'AppPasswordCreate',
            'label',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
