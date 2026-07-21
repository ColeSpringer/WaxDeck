// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ws_ping_frame.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WsPingFrame extends WsPingFrame {
  @override
  final String type;
  @override
  final int t;

  factory _$WsPingFrame([void Function(WsPingFrameBuilder)? updates]) =>
      (WsPingFrameBuilder()..update(updates))._build();

  _$WsPingFrame._({required this.type, required this.t}) : super._();
  @override
  WsPingFrame rebuild(void Function(WsPingFrameBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WsPingFrameBuilder toBuilder() => WsPingFrameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WsPingFrame && type == other.type && t == other.t;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, t.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WsPingFrame')
          ..add('type', type)
          ..add('t', t))
        .toString();
  }
}

class WsPingFrameBuilder implements Builder<WsPingFrame, WsPingFrameBuilder> {
  _$WsPingFrame? _$v;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  int? _t;
  int? get t => _$this._t;
  set t(int? t) => _$this._t = t;

  WsPingFrameBuilder() {
    WsPingFrame._defaults(this);
  }

  WsPingFrameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _t = $v.t;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WsPingFrame other) {
    _$v = other as _$WsPingFrame;
  }

  @override
  void update(void Function(WsPingFrameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WsPingFrame build() => _build();

  _$WsPingFrame _build() {
    final _$result =
        _$v ??
        _$WsPingFrame._(
          type: BuiltValueNullFieldError.checkNotNull(
            type,
            r'WsPingFrame',
            'type',
          ),
          t: BuiltValueNullFieldError.checkNotNull(t, r'WsPingFrame', 't'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
