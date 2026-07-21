// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ws_command_result_frame.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WsCommandResultFrame extends WsCommandResultFrame {
  @override
  final String type;
  @override
  final String id;
  @override
  final bool ok;
  @override
  final String? code;
  @override
  final String? message;

  factory _$WsCommandResultFrame([
    void Function(WsCommandResultFrameBuilder)? updates,
  ]) => (WsCommandResultFrameBuilder()..update(updates))._build();

  _$WsCommandResultFrame._({
    required this.type,
    required this.id,
    required this.ok,
    this.code,
    this.message,
  }) : super._();
  @override
  WsCommandResultFrame rebuild(
    void Function(WsCommandResultFrameBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  WsCommandResultFrameBuilder toBuilder() =>
      WsCommandResultFrameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WsCommandResultFrame &&
        type == other.type &&
        id == other.id &&
        ok == other.ok &&
        code == other.code &&
        message == other.message;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, ok.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WsCommandResultFrame')
          ..add('type', type)
          ..add('id', id)
          ..add('ok', ok)
          ..add('code', code)
          ..add('message', message))
        .toString();
  }
}

class WsCommandResultFrameBuilder
    implements Builder<WsCommandResultFrame, WsCommandResultFrameBuilder> {
  _$WsCommandResultFrame? _$v;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  bool? _ok;
  bool? get ok => _$this._ok;
  set ok(bool? ok) => _$this._ok = ok;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  WsCommandResultFrameBuilder() {
    WsCommandResultFrame._defaults(this);
  }

  WsCommandResultFrameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _id = $v.id;
      _ok = $v.ok;
      _code = $v.code;
      _message = $v.message;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WsCommandResultFrame other) {
    _$v = other as _$WsCommandResultFrame;
  }

  @override
  void update(void Function(WsCommandResultFrameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WsCommandResultFrame build() => _build();

  _$WsCommandResultFrame _build() {
    final _$result =
        _$v ??
        _$WsCommandResultFrame._(
          type: BuiltValueNullFieldError.checkNotNull(
            type,
            r'WsCommandResultFrame',
            'type',
          ),
          id: BuiltValueNullFieldError.checkNotNull(
            id,
            r'WsCommandResultFrame',
            'id',
          ),
          ok: BuiltValueNullFieldError.checkNotNull(
            ok,
            r'WsCommandResultFrame',
            'ok',
          ),
          code: code,
          message: message,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
