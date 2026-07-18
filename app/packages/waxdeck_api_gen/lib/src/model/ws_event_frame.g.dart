// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ws_event_frame.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WsEventFrame extends WsEventFrame {
  @override
  final String type;
  @override
  final String? topic;

  factory _$WsEventFrame([void Function(WsEventFrameBuilder)? updates]) =>
      (WsEventFrameBuilder()..update(updates))._build();

  _$WsEventFrame._({required this.type, this.topic}) : super._();
  @override
  WsEventFrame rebuild(void Function(WsEventFrameBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WsEventFrameBuilder toBuilder() => WsEventFrameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WsEventFrame && type == other.type && topic == other.topic;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, topic.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WsEventFrame')
          ..add('type', type)
          ..add('topic', topic))
        .toString();
  }
}

class WsEventFrameBuilder
    implements Builder<WsEventFrame, WsEventFrameBuilder> {
  _$WsEventFrame? _$v;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  String? _topic;
  String? get topic => _$this._topic;
  set topic(String? topic) => _$this._topic = topic;

  WsEventFrameBuilder() {
    WsEventFrame._defaults(this);
  }

  WsEventFrameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _topic = $v.topic;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WsEventFrame other) {
    _$v = other as _$WsEventFrame;
  }

  @override
  void update(void Function(WsEventFrameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WsEventFrame build() => _build();

  _$WsEventFrame _build() {
    final _$result =
        _$v ??
        _$WsEventFrame._(
          type: BuiltValueNullFieldError.checkNotNull(
            type,
            r'WsEventFrame',
            'type',
          ),
          topic: topic,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
