// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bootstrap_status.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BootstrapStatus extends BootstrapStatus {
  @override
  final bool required_;
  @override
  final bool? signupEnabled;

  factory _$BootstrapStatus([void Function(BootstrapStatusBuilder)? updates]) =>
      (BootstrapStatusBuilder()..update(updates))._build();

  _$BootstrapStatus._({required this.required_, this.signupEnabled})
    : super._();
  @override
  BootstrapStatus rebuild(void Function(BootstrapStatusBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BootstrapStatusBuilder toBuilder() => BootstrapStatusBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BootstrapStatus &&
        required_ == other.required_ &&
        signupEnabled == other.signupEnabled;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, required_.hashCode);
    _$hash = $jc(_$hash, signupEnabled.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BootstrapStatus')
          ..add('required_', required_)
          ..add('signupEnabled', signupEnabled))
        .toString();
  }
}

class BootstrapStatusBuilder
    implements Builder<BootstrapStatus, BootstrapStatusBuilder> {
  _$BootstrapStatus? _$v;

  bool? _required_;
  bool? get required_ => _$this._required_;
  set required_(bool? required_) => _$this._required_ = required_;

  bool? _signupEnabled;
  bool? get signupEnabled => _$this._signupEnabled;
  set signupEnabled(bool? signupEnabled) =>
      _$this._signupEnabled = signupEnabled;

  BootstrapStatusBuilder() {
    BootstrapStatus._defaults(this);
  }

  BootstrapStatusBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _required_ = $v.required_;
      _signupEnabled = $v.signupEnabled;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BootstrapStatus other) {
    _$v = other as _$BootstrapStatus;
  }

  @override
  void update(void Function(BootstrapStatusBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BootstrapStatus build() => _build();

  _$BootstrapStatus _build() {
    final _$result =
        _$v ??
        _$BootstrapStatus._(
          required_: BuiltValueNullFieldError.checkNotNull(
            required_,
            r'BootstrapStatus',
            'required_',
          ),
          signupEnabled: signupEnabled,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
