// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'signup_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const SignupResultStateEnum _$signupResultStateEnum_pending =
    const SignupResultStateEnum._('pending');
const SignupResultStateEnum _$signupResultStateEnum_active =
    const SignupResultStateEnum._('active');
const SignupResultStateEnum _$signupResultStateEnum_unknownDefaultOpenApi =
    const SignupResultStateEnum._('unknownDefaultOpenApi');

SignupResultStateEnum _$signupResultStateEnumValueOf(String name) {
  switch (name) {
    case 'pending':
      return _$signupResultStateEnum_pending;
    case 'active':
      return _$signupResultStateEnum_active;
    case 'unknownDefaultOpenApi':
      return _$signupResultStateEnum_unknownDefaultOpenApi;
    default:
      return _$signupResultStateEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<SignupResultStateEnum> _$signupResultStateEnumValues =
    BuiltSet<SignupResultStateEnum>(const <SignupResultStateEnum>[
      _$signupResultStateEnum_pending,
      _$signupResultStateEnum_active,
      _$signupResultStateEnum_unknownDefaultOpenApi,
    ]);

Serializer<SignupResultStateEnum> _$signupResultStateEnumSerializer =
    _$SignupResultStateEnumSerializer();

class _$SignupResultStateEnumSerializer
    implements PrimitiveSerializer<SignupResultStateEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'pending': 'pending',
    'active': 'active',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'pending': 'pending',
    'active': 'active',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[SignupResultStateEnum];
  @override
  final String wireName = 'SignupResultStateEnum';

  @override
  Object serialize(
    Serializers serializers,
    SignupResultStateEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  SignupResultStateEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => SignupResultStateEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$SignupResult extends SignupResult {
  @override
  final SignupResultStateEnum state;

  factory _$SignupResult([void Function(SignupResultBuilder)? updates]) =>
      (SignupResultBuilder()..update(updates))._build();

  _$SignupResult._({required this.state}) : super._();
  @override
  SignupResult rebuild(void Function(SignupResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SignupResultBuilder toBuilder() => SignupResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SignupResult && state == other.state;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, state.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'SignupResult',
    )..add('state', state)).toString();
  }
}

class SignupResultBuilder
    implements Builder<SignupResult, SignupResultBuilder> {
  _$SignupResult? _$v;

  SignupResultStateEnum? _state;
  SignupResultStateEnum? get state => _$this._state;
  set state(SignupResultStateEnum? state) => _$this._state = state;

  SignupResultBuilder() {
    SignupResult._defaults(this);
  }

  SignupResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _state = $v.state;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SignupResult other) {
    _$v = other as _$SignupResult;
  }

  @override
  void update(void Function(SignupResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SignupResult build() => _build();

  _$SignupResult _build() {
    final _$result =
        _$v ??
        _$SignupResult._(
          state: BuiltValueNullFieldError.checkNotNull(
            state,
            r'SignupResult',
            'state',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
