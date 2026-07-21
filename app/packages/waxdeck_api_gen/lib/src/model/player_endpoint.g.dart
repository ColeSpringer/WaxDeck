// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_endpoint.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlayerEndpoint extends PlayerEndpoint {
  @override
  final String id;
  @override
  final String kind;
  @override
  final String name;
  @override
  final bool online;
  @override
  final bool shared;
  @override
  final bool mine;
  @override
  final bool volumeControl;
  @override
  final bool rateControl;
  @override
  final String? activeSessionId;

  factory _$PlayerEndpoint([void Function(PlayerEndpointBuilder)? updates]) =>
      (PlayerEndpointBuilder()..update(updates))._build();

  _$PlayerEndpoint._({
    required this.id,
    required this.kind,
    required this.name,
    required this.online,
    required this.shared,
    required this.mine,
    required this.volumeControl,
    required this.rateControl,
    this.activeSessionId,
  }) : super._();
  @override
  PlayerEndpoint rebuild(void Function(PlayerEndpointBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlayerEndpointBuilder toBuilder() => PlayerEndpointBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlayerEndpoint &&
        id == other.id &&
        kind == other.kind &&
        name == other.name &&
        online == other.online &&
        shared == other.shared &&
        mine == other.mine &&
        volumeControl == other.volumeControl &&
        rateControl == other.rateControl &&
        activeSessionId == other.activeSessionId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, online.hashCode);
    _$hash = $jc(_$hash, shared.hashCode);
    _$hash = $jc(_$hash, mine.hashCode);
    _$hash = $jc(_$hash, volumeControl.hashCode);
    _$hash = $jc(_$hash, rateControl.hashCode);
    _$hash = $jc(_$hash, activeSessionId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlayerEndpoint')
          ..add('id', id)
          ..add('kind', kind)
          ..add('name', name)
          ..add('online', online)
          ..add('shared', shared)
          ..add('mine', mine)
          ..add('volumeControl', volumeControl)
          ..add('rateControl', rateControl)
          ..add('activeSessionId', activeSessionId))
        .toString();
  }
}

class PlayerEndpointBuilder
    implements Builder<PlayerEndpoint, PlayerEndpointBuilder> {
  _$PlayerEndpoint? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _kind;
  String? get kind => _$this._kind;
  set kind(String? kind) => _$this._kind = kind;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  bool? _online;
  bool? get online => _$this._online;
  set online(bool? online) => _$this._online = online;

  bool? _shared;
  bool? get shared => _$this._shared;
  set shared(bool? shared) => _$this._shared = shared;

  bool? _mine;
  bool? get mine => _$this._mine;
  set mine(bool? mine) => _$this._mine = mine;

  bool? _volumeControl;
  bool? get volumeControl => _$this._volumeControl;
  set volumeControl(bool? volumeControl) =>
      _$this._volumeControl = volumeControl;

  bool? _rateControl;
  bool? get rateControl => _$this._rateControl;
  set rateControl(bool? rateControl) => _$this._rateControl = rateControl;

  String? _activeSessionId;
  String? get activeSessionId => _$this._activeSessionId;
  set activeSessionId(String? activeSessionId) =>
      _$this._activeSessionId = activeSessionId;

  PlayerEndpointBuilder() {
    PlayerEndpoint._defaults(this);
  }

  PlayerEndpointBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _kind = $v.kind;
      _name = $v.name;
      _online = $v.online;
      _shared = $v.shared;
      _mine = $v.mine;
      _volumeControl = $v.volumeControl;
      _rateControl = $v.rateControl;
      _activeSessionId = $v.activeSessionId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlayerEndpoint other) {
    _$v = other as _$PlayerEndpoint;
  }

  @override
  void update(void Function(PlayerEndpointBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlayerEndpoint build() => _build();

  _$PlayerEndpoint _build() {
    final _$result =
        _$v ??
        _$PlayerEndpoint._(
          id: BuiltValueNullFieldError.checkNotNull(
            id,
            r'PlayerEndpoint',
            'id',
          ),
          kind: BuiltValueNullFieldError.checkNotNull(
            kind,
            r'PlayerEndpoint',
            'kind',
          ),
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'PlayerEndpoint',
            'name',
          ),
          online: BuiltValueNullFieldError.checkNotNull(
            online,
            r'PlayerEndpoint',
            'online',
          ),
          shared: BuiltValueNullFieldError.checkNotNull(
            shared,
            r'PlayerEndpoint',
            'shared',
          ),
          mine: BuiltValueNullFieldError.checkNotNull(
            mine,
            r'PlayerEndpoint',
            'mine',
          ),
          volumeControl: BuiltValueNullFieldError.checkNotNull(
            volumeControl,
            r'PlayerEndpoint',
            'volumeControl',
          ),
          rateControl: BuiltValueNullFieldError.checkNotNull(
            rateControl,
            r'PlayerEndpoint',
            'rateControl',
          ),
          activeSessionId: activeSessionId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
