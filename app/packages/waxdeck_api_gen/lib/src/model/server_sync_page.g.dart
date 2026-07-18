// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_sync_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ServerSyncPage extends ServerSyncPage {
  @override
  final BuiltList<ServerSyncEvent> events;
  @override
  final String nextSince;
  @override
  final bool? more;

  factory _$ServerSyncPage([void Function(ServerSyncPageBuilder)? updates]) =>
      (ServerSyncPageBuilder()..update(updates))._build();

  _$ServerSyncPage._({required this.events, required this.nextSince, this.more})
    : super._();
  @override
  ServerSyncPage rebuild(void Function(ServerSyncPageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ServerSyncPageBuilder toBuilder() => ServerSyncPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServerSyncPage &&
        events == other.events &&
        nextSince == other.nextSince &&
        more == other.more;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, events.hashCode);
    _$hash = $jc(_$hash, nextSince.hashCode);
    _$hash = $jc(_$hash, more.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ServerSyncPage')
          ..add('events', events)
          ..add('nextSince', nextSince)
          ..add('more', more))
        .toString();
  }
}

class ServerSyncPageBuilder
    implements Builder<ServerSyncPage, ServerSyncPageBuilder> {
  _$ServerSyncPage? _$v;

  ListBuilder<ServerSyncEvent>? _events;
  ListBuilder<ServerSyncEvent> get events =>
      _$this._events ??= ListBuilder<ServerSyncEvent>();
  set events(ListBuilder<ServerSyncEvent>? events) => _$this._events = events;

  String? _nextSince;
  String? get nextSince => _$this._nextSince;
  set nextSince(String? nextSince) => _$this._nextSince = nextSince;

  bool? _more;
  bool? get more => _$this._more;
  set more(bool? more) => _$this._more = more;

  ServerSyncPageBuilder() {
    ServerSyncPage._defaults(this);
  }

  ServerSyncPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _events = $v.events.toBuilder();
      _nextSince = $v.nextSince;
      _more = $v.more;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServerSyncPage other) {
    _$v = other as _$ServerSyncPage;
  }

  @override
  void update(void Function(ServerSyncPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ServerSyncPage build() => _build();

  _$ServerSyncPage _build() {
    _$ServerSyncPage _$result;
    try {
      _$result =
          _$v ??
          _$ServerSyncPage._(
            events: events.build(),
            nextSince: BuiltValueNullFieldError.checkNotNull(
              nextSince,
              r'ServerSyncPage',
              'nextSince',
            ),
            more: more,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'events';
        events.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ServerSyncPage',
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
