// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ws_register_endpoint_frame.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WsRegisterEndpointFrame extends WsRegisterEndpointFrame {
  @override
  final String type;
  @override
  final String id;
  @override
  final String? name;
  @override
  final bool? volumeControl;
  @override
  final bool? rateControl;

  factory _$WsRegisterEndpointFrame([
    void Function(WsRegisterEndpointFrameBuilder)? updates,
  ]) => (WsRegisterEndpointFrameBuilder()..update(updates))._build();

  _$WsRegisterEndpointFrame._({
    required this.type,
    required this.id,
    this.name,
    this.volumeControl,
    this.rateControl,
  }) : super._();
  @override
  WsRegisterEndpointFrame rebuild(
    void Function(WsRegisterEndpointFrameBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  WsRegisterEndpointFrameBuilder toBuilder() =>
      WsRegisterEndpointFrameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WsRegisterEndpointFrame &&
        type == other.type &&
        id == other.id &&
        name == other.name &&
        volumeControl == other.volumeControl &&
        rateControl == other.rateControl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, volumeControl.hashCode);
    _$hash = $jc(_$hash, rateControl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WsRegisterEndpointFrame')
          ..add('type', type)
          ..add('id', id)
          ..add('name', name)
          ..add('volumeControl', volumeControl)
          ..add('rateControl', rateControl))
        .toString();
  }
}

class WsRegisterEndpointFrameBuilder
    implements
        Builder<WsRegisterEndpointFrame, WsRegisterEndpointFrameBuilder> {
  _$WsRegisterEndpointFrame? _$v;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  bool? _volumeControl;
  bool? get volumeControl => _$this._volumeControl;
  set volumeControl(bool? volumeControl) =>
      _$this._volumeControl = volumeControl;

  bool? _rateControl;
  bool? get rateControl => _$this._rateControl;
  set rateControl(bool? rateControl) => _$this._rateControl = rateControl;

  WsRegisterEndpointFrameBuilder() {
    WsRegisterEndpointFrame._defaults(this);
  }

  WsRegisterEndpointFrameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _id = $v.id;
      _name = $v.name;
      _volumeControl = $v.volumeControl;
      _rateControl = $v.rateControl;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WsRegisterEndpointFrame other) {
    _$v = other as _$WsRegisterEndpointFrame;
  }

  @override
  void update(void Function(WsRegisterEndpointFrameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WsRegisterEndpointFrame build() => _build();

  _$WsRegisterEndpointFrame _build() {
    final _$result =
        _$v ??
        _$WsRegisterEndpointFrame._(
          type: BuiltValueNullFieldError.checkNotNull(
            type,
            r'WsRegisterEndpointFrame',
            'type',
          ),
          id: BuiltValueNullFieldError.checkNotNull(
            id,
            r'WsRegisterEndpointFrame',
            'id',
          ),
          name: name,
          volumeControl: volumeControl,
          rateControl: rateControl,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
