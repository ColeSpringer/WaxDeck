// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_registration_create.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PushRegistrationCreate extends PushRegistrationCreate {
  @override
  final String endpoint;
  @override
  final String? label;

  factory _$PushRegistrationCreate([
    void Function(PushRegistrationCreateBuilder)? updates,
  ]) => (PushRegistrationCreateBuilder()..update(updates))._build();

  _$PushRegistrationCreate._({required this.endpoint, this.label}) : super._();
  @override
  PushRegistrationCreate rebuild(
    void Function(PushRegistrationCreateBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PushRegistrationCreateBuilder toBuilder() =>
      PushRegistrationCreateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PushRegistrationCreate &&
        endpoint == other.endpoint &&
        label == other.label;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, endpoint.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PushRegistrationCreate')
          ..add('endpoint', endpoint)
          ..add('label', label))
        .toString();
  }
}

class PushRegistrationCreateBuilder
    implements Builder<PushRegistrationCreate, PushRegistrationCreateBuilder> {
  _$PushRegistrationCreate? _$v;

  String? _endpoint;
  String? get endpoint => _$this._endpoint;
  set endpoint(String? endpoint) => _$this._endpoint = endpoint;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  PushRegistrationCreateBuilder() {
    PushRegistrationCreate._defaults(this);
  }

  PushRegistrationCreateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _endpoint = $v.endpoint;
      _label = $v.label;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PushRegistrationCreate other) {
    _$v = other as _$PushRegistrationCreate;
  }

  @override
  void update(void Function(PushRegistrationCreateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PushRegistrationCreate build() => _build();

  _$PushRegistrationCreate _build() {
    final _$result =
        _$v ??
        _$PushRegistrationCreate._(
          endpoint: BuiltValueNullFieldError.checkNotNull(
            endpoint,
            r'PushRegistrationCreate',
            'endpoint',
          ),
          label: label,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
