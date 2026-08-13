// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ws_error_frame.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WsErrorFrame extends WsErrorFrame {
  @override
  final String type;
  @override
  final String? id;
  @override
  final String code;
  @override
  final String message;
  @override
  final BuiltMap<String, String>? params;

  factory _$WsErrorFrame([void Function(WsErrorFrameBuilder)? updates]) =>
      (WsErrorFrameBuilder()..update(updates))._build();

  _$WsErrorFrame._({
    required this.type,
    this.id,
    required this.code,
    required this.message,
    this.params,
  }) : super._();
  @override
  WsErrorFrame rebuild(void Function(WsErrorFrameBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WsErrorFrameBuilder toBuilder() => WsErrorFrameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WsErrorFrame &&
        type == other.type &&
        id == other.id &&
        code == other.code &&
        message == other.message &&
        params == other.params;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jc(_$hash, params.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WsErrorFrame')
          ..add('type', type)
          ..add('id', id)
          ..add('code', code)
          ..add('message', message)
          ..add('params', params))
        .toString();
  }
}

class WsErrorFrameBuilder
    implements Builder<WsErrorFrame, WsErrorFrameBuilder> {
  _$WsErrorFrame? _$v;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _params;
  MapBuilder<String, String> get params =>
      _$this._params ??= MapBuilder<String, String>();
  set params(MapBuilder<String, String>? params) => _$this._params = params;

  WsErrorFrameBuilder() {
    WsErrorFrame._defaults(this);
  }

  WsErrorFrameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _id = $v.id;
      _code = $v.code;
      _message = $v.message;
      _params = $v.params?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WsErrorFrame other) {
    _$v = other as _$WsErrorFrame;
  }

  @override
  void update(void Function(WsErrorFrameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WsErrorFrame build() => _build();

  _$WsErrorFrame _build() {
    _$WsErrorFrame _$result;
    try {
      _$result =
          _$v ??
          _$WsErrorFrame._(
            type: BuiltValueNullFieldError.checkNotNull(
              type,
              r'WsErrorFrame',
              'type',
            ),
            id: id,
            code: BuiltValueNullFieldError.checkNotNull(
              code,
              r'WsErrorFrame',
              'code',
            ),
            message: BuiltValueNullFieldError.checkNotNull(
              message,
              r'WsErrorFrame',
              'message',
            ),
            params: _params?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'params';
        _params?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'WsErrorFrame',
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
