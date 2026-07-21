// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_endpoint_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlayerEndpointList extends PlayerEndpointList {
  @override
  final BuiltList<PlayerEndpoint> endpoints;

  factory _$PlayerEndpointList([
    void Function(PlayerEndpointListBuilder)? updates,
  ]) => (PlayerEndpointListBuilder()..update(updates))._build();

  _$PlayerEndpointList._({required this.endpoints}) : super._();
  @override
  PlayerEndpointList rebuild(
    void Function(PlayerEndpointListBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PlayerEndpointListBuilder toBuilder() =>
      PlayerEndpointListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlayerEndpointList && endpoints == other.endpoints;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, endpoints.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'PlayerEndpointList',
    )..add('endpoints', endpoints)).toString();
  }
}

class PlayerEndpointListBuilder
    implements Builder<PlayerEndpointList, PlayerEndpointListBuilder> {
  _$PlayerEndpointList? _$v;

  ListBuilder<PlayerEndpoint>? _endpoints;
  ListBuilder<PlayerEndpoint> get endpoints =>
      _$this._endpoints ??= ListBuilder<PlayerEndpoint>();
  set endpoints(ListBuilder<PlayerEndpoint>? endpoints) =>
      _$this._endpoints = endpoints;

  PlayerEndpointListBuilder() {
    PlayerEndpointList._defaults(this);
  }

  PlayerEndpointListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _endpoints = $v.endpoints.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlayerEndpointList other) {
    _$v = other as _$PlayerEndpointList;
  }

  @override
  void update(void Function(PlayerEndpointListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlayerEndpointList build() => _build();

  _$PlayerEndpointList _build() {
    _$PlayerEndpointList _$result;
    try {
      _$result = _$v ?? _$PlayerEndpointList._(endpoints: endpoints.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'endpoints';
        endpoints.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlayerEndpointList',
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
