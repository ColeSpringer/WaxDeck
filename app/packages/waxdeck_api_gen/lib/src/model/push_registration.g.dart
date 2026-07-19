// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_registration.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PushRegistration extends PushRegistration {
  @override
  final String pid;
  @override
  final String endpoint;
  @override
  final String? label;
  @override
  final DateTime createdAt;

  factory _$PushRegistration([
    void Function(PushRegistrationBuilder)? updates,
  ]) => (PushRegistrationBuilder()..update(updates))._build();

  _$PushRegistration._({
    required this.pid,
    required this.endpoint,
    this.label,
    required this.createdAt,
  }) : super._();
  @override
  PushRegistration rebuild(void Function(PushRegistrationBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PushRegistrationBuilder toBuilder() =>
      PushRegistrationBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PushRegistration &&
        pid == other.pid &&
        endpoint == other.endpoint &&
        label == other.label &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, endpoint.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PushRegistration')
          ..add('pid', pid)
          ..add('endpoint', endpoint)
          ..add('label', label)
          ..add('createdAt', createdAt))
        .toString();
  }
}

class PushRegistrationBuilder
    implements Builder<PushRegistration, PushRegistrationBuilder> {
  _$PushRegistration? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _endpoint;
  String? get endpoint => _$this._endpoint;
  set endpoint(String? endpoint) => _$this._endpoint = endpoint;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  PushRegistrationBuilder() {
    PushRegistration._defaults(this);
  }

  PushRegistrationBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _endpoint = $v.endpoint;
      _label = $v.label;
      _createdAt = $v.createdAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PushRegistration other) {
    _$v = other as _$PushRegistration;
  }

  @override
  void update(void Function(PushRegistrationBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PushRegistration build() => _build();

  _$PushRegistration _build() {
    final _$result =
        _$v ??
        _$PushRegistration._(
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'PushRegistration',
            'pid',
          ),
          endpoint: BuiltValueNullFieldError.checkNotNull(
            endpoint,
            r'PushRegistration',
            'endpoint',
          ),
          label: label,
          createdAt: BuiltValueNullFieldError.checkNotNull(
            createdAt,
            r'PushRegistration',
            'createdAt',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
