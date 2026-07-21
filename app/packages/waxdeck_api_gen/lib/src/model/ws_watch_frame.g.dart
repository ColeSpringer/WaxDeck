// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ws_watch_frame.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WsWatchFrame extends WsWatchFrame {
  @override
  final String type;
  @override
  final String? id;
  @override
  final String? sessionId;

  factory _$WsWatchFrame([void Function(WsWatchFrameBuilder)? updates]) =>
      (WsWatchFrameBuilder()..update(updates))._build();

  _$WsWatchFrame._({required this.type, this.id, this.sessionId}) : super._();
  @override
  WsWatchFrame rebuild(void Function(WsWatchFrameBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WsWatchFrameBuilder toBuilder() => WsWatchFrameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WsWatchFrame &&
        type == other.type &&
        id == other.id &&
        sessionId == other.sessionId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, sessionId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WsWatchFrame')
          ..add('type', type)
          ..add('id', id)
          ..add('sessionId', sessionId))
        .toString();
  }
}

class WsWatchFrameBuilder
    implements Builder<WsWatchFrame, WsWatchFrameBuilder> {
  _$WsWatchFrame? _$v;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _sessionId;
  String? get sessionId => _$this._sessionId;
  set sessionId(String? sessionId) => _$this._sessionId = sessionId;

  WsWatchFrameBuilder() {
    WsWatchFrame._defaults(this);
  }

  WsWatchFrameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _id = $v.id;
      _sessionId = $v.sessionId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WsWatchFrame other) {
    _$v = other as _$WsWatchFrame;
  }

  @override
  void update(void Function(WsWatchFrameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WsWatchFrame build() => _build();

  _$WsWatchFrame _build() {
    final _$result =
        _$v ??
        _$WsWatchFrame._(
          type: BuiltValueNullFieldError.checkNotNull(
            type,
            r'WsWatchFrame',
            'type',
          ),
          id: id,
          sessionId: sessionId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
