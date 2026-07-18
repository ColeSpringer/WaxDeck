// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ws_subscribe_frame.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WsSubscribeFrame extends WsSubscribeFrame {
  @override
  final String? catalogSince;
  @override
  final String? serverSince;
  @override
  final BuiltList<String>? topics;

  factory _$WsSubscribeFrame([
    void Function(WsSubscribeFrameBuilder)? updates,
  ]) => (WsSubscribeFrameBuilder()..update(updates))._build();

  _$WsSubscribeFrame._({this.catalogSince, this.serverSince, this.topics})
    : super._();
  @override
  WsSubscribeFrame rebuild(void Function(WsSubscribeFrameBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WsSubscribeFrameBuilder toBuilder() =>
      WsSubscribeFrameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WsSubscribeFrame &&
        catalogSince == other.catalogSince &&
        serverSince == other.serverSince &&
        topics == other.topics;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, catalogSince.hashCode);
    _$hash = $jc(_$hash, serverSince.hashCode);
    _$hash = $jc(_$hash, topics.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WsSubscribeFrame')
          ..add('catalogSince', catalogSince)
          ..add('serverSince', serverSince)
          ..add('topics', topics))
        .toString();
  }
}

class WsSubscribeFrameBuilder
    implements Builder<WsSubscribeFrame, WsSubscribeFrameBuilder> {
  _$WsSubscribeFrame? _$v;

  String? _catalogSince;
  String? get catalogSince => _$this._catalogSince;
  set catalogSince(String? catalogSince) => _$this._catalogSince = catalogSince;

  String? _serverSince;
  String? get serverSince => _$this._serverSince;
  set serverSince(String? serverSince) => _$this._serverSince = serverSince;

  ListBuilder<String>? _topics;
  ListBuilder<String> get topics => _$this._topics ??= ListBuilder<String>();
  set topics(ListBuilder<String>? topics) => _$this._topics = topics;

  WsSubscribeFrameBuilder() {
    WsSubscribeFrame._defaults(this);
  }

  WsSubscribeFrameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _catalogSince = $v.catalogSince;
      _serverSince = $v.serverSince;
      _topics = $v.topics?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WsSubscribeFrame other) {
    _$v = other as _$WsSubscribeFrame;
  }

  @override
  void update(void Function(WsSubscribeFrameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WsSubscribeFrame build() => _build();

  _$WsSubscribeFrame _build() {
    _$WsSubscribeFrame _$result;
    try {
      _$result =
          _$v ??
          _$WsSubscribeFrame._(
            catalogSince: catalogSince,
            serverSince: serverSince,
            topics: _topics?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'topics';
        _topics?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'WsSubscribeFrame',
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
