// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rejected_listen.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RejectedListen extends RejectedListen {
  @override
  final String sessionId;
  @override
  final String code;
  @override
  final String message;

  factory _$RejectedListen([void Function(RejectedListenBuilder)? updates]) =>
      (RejectedListenBuilder()..update(updates))._build();

  _$RejectedListen._({
    required this.sessionId,
    required this.code,
    required this.message,
  }) : super._();
  @override
  RejectedListen rebuild(void Function(RejectedListenBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RejectedListenBuilder toBuilder() => RejectedListenBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RejectedListen &&
        sessionId == other.sessionId &&
        code == other.code &&
        message == other.message;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, sessionId.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RejectedListen')
          ..add('sessionId', sessionId)
          ..add('code', code)
          ..add('message', message))
        .toString();
  }
}

class RejectedListenBuilder
    implements Builder<RejectedListen, RejectedListenBuilder> {
  _$RejectedListen? _$v;

  String? _sessionId;
  String? get sessionId => _$this._sessionId;
  set sessionId(String? sessionId) => _$this._sessionId = sessionId;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  RejectedListenBuilder() {
    RejectedListen._defaults(this);
  }

  RejectedListenBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sessionId = $v.sessionId;
      _code = $v.code;
      _message = $v.message;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RejectedListen other) {
    _$v = other as _$RejectedListen;
  }

  @override
  void update(void Function(RejectedListenBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RejectedListen build() => _build();

  _$RejectedListen _build() {
    final _$result =
        _$v ??
        _$RejectedListen._(
          sessionId: BuiltValueNullFieldError.checkNotNull(
            sessionId,
            r'RejectedListen',
            'sessionId',
          ),
          code: BuiltValueNullFieldError.checkNotNull(
            code,
            r'RejectedListen',
            'code',
          ),
          message: BuiltValueNullFieldError.checkNotNull(
            message,
            r'RejectedListen',
            'message',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
