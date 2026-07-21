// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ws_session_frame.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WsSessionFrame extends WsSessionFrame {
  @override
  final String type;
  @override
  final PlaybackSession session;

  factory _$WsSessionFrame([void Function(WsSessionFrameBuilder)? updates]) =>
      (WsSessionFrameBuilder()..update(updates))._build();

  _$WsSessionFrame._({required this.type, required this.session}) : super._();
  @override
  WsSessionFrame rebuild(void Function(WsSessionFrameBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WsSessionFrameBuilder toBuilder() => WsSessionFrameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WsSessionFrame &&
        type == other.type &&
        session == other.session;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, session.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WsSessionFrame')
          ..add('type', type)
          ..add('session', session))
        .toString();
  }
}

class WsSessionFrameBuilder
    implements Builder<WsSessionFrame, WsSessionFrameBuilder> {
  _$WsSessionFrame? _$v;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  PlaybackSessionBuilder? _session;
  PlaybackSessionBuilder get session =>
      _$this._session ??= PlaybackSessionBuilder();
  set session(PlaybackSessionBuilder? session) => _$this._session = session;

  WsSessionFrameBuilder() {
    WsSessionFrame._defaults(this);
  }

  WsSessionFrameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _session = $v.session.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WsSessionFrame other) {
    _$v = other as _$WsSessionFrame;
  }

  @override
  void update(void Function(WsSessionFrameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WsSessionFrame build() => _build();

  _$WsSessionFrame _build() {
    _$WsSessionFrame _$result;
    try {
      _$result =
          _$v ??
          _$WsSessionFrame._(
            type: BuiltValueNullFieldError.checkNotNull(
              type,
              r'WsSessionFrame',
              'type',
            ),
            session: session.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'session';
        session.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'WsSessionFrame',
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
