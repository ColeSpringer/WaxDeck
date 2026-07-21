// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ws_pong_frame.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WsPongFrame extends WsPongFrame {
  @override
  final String type;
  @override
  final int t;
  @override
  final int at;

  factory _$WsPongFrame([void Function(WsPongFrameBuilder)? updates]) =>
      (WsPongFrameBuilder()..update(updates))._build();

  _$WsPongFrame._({required this.type, required this.t, required this.at})
    : super._();
  @override
  WsPongFrame rebuild(void Function(WsPongFrameBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WsPongFrameBuilder toBuilder() => WsPongFrameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WsPongFrame &&
        type == other.type &&
        t == other.t &&
        at == other.at;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, t.hashCode);
    _$hash = $jc(_$hash, at.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WsPongFrame')
          ..add('type', type)
          ..add('t', t)
          ..add('at', at))
        .toString();
  }
}

class WsPongFrameBuilder implements Builder<WsPongFrame, WsPongFrameBuilder> {
  _$WsPongFrame? _$v;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  int? _t;
  int? get t => _$this._t;
  set t(int? t) => _$this._t = t;

  int? _at;
  int? get at => _$this._at;
  set at(int? at) => _$this._at = at;

  WsPongFrameBuilder() {
    WsPongFrame._defaults(this);
  }

  WsPongFrameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _t = $v.t;
      _at = $v.at;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WsPongFrame other) {
    _$v = other as _$WsPongFrame;
  }

  @override
  void update(void Function(WsPongFrameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WsPongFrame build() => _build();

  _$WsPongFrame _build() {
    final _$result =
        _$v ??
        _$WsPongFrame._(
          type: BuiltValueNullFieldError.checkNotNull(
            type,
            r'WsPongFrame',
            'type',
          ),
          t: BuiltValueNullFieldError.checkNotNull(t, r'WsPongFrame', 't'),
          at: BuiltValueNullFieldError.checkNotNull(at, r'WsPongFrame', 'at'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
