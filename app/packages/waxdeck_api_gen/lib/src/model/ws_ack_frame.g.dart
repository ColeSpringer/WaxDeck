// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ws_ack_frame.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WsAckFrame extends WsAckFrame {
  @override
  final String type;
  @override
  final String id;
  @override
  final String? endpointId;
  @override
  final PlaybackSession? session;

  factory _$WsAckFrame([void Function(WsAckFrameBuilder)? updates]) =>
      (WsAckFrameBuilder()..update(updates))._build();

  _$WsAckFrame._({
    required this.type,
    required this.id,
    this.endpointId,
    this.session,
  }) : super._();
  @override
  WsAckFrame rebuild(void Function(WsAckFrameBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WsAckFrameBuilder toBuilder() => WsAckFrameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WsAckFrame &&
        type == other.type &&
        id == other.id &&
        endpointId == other.endpointId &&
        session == other.session;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, endpointId.hashCode);
    _$hash = $jc(_$hash, session.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WsAckFrame')
          ..add('type', type)
          ..add('id', id)
          ..add('endpointId', endpointId)
          ..add('session', session))
        .toString();
  }
}

class WsAckFrameBuilder implements Builder<WsAckFrame, WsAckFrameBuilder> {
  _$WsAckFrame? _$v;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _endpointId;
  String? get endpointId => _$this._endpointId;
  set endpointId(String? endpointId) => _$this._endpointId = endpointId;

  PlaybackSessionBuilder? _session;
  PlaybackSessionBuilder get session =>
      _$this._session ??= PlaybackSessionBuilder();
  set session(PlaybackSessionBuilder? session) => _$this._session = session;

  WsAckFrameBuilder() {
    WsAckFrame._defaults(this);
  }

  WsAckFrameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _id = $v.id;
      _endpointId = $v.endpointId;
      _session = $v.session?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WsAckFrame other) {
    _$v = other as _$WsAckFrame;
  }

  @override
  void update(void Function(WsAckFrameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WsAckFrame build() => _build();

  _$WsAckFrame _build() {
    _$WsAckFrame _$result;
    try {
      _$result =
          _$v ??
          _$WsAckFrame._(
            type: BuiltValueNullFieldError.checkNotNull(
              type,
              r'WsAckFrame',
              'type',
            ),
            id: BuiltValueNullFieldError.checkNotNull(id, r'WsAckFrame', 'id'),
            endpointId: endpointId,
            session: _session?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'session';
        _session?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'WsAckFrame',
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
