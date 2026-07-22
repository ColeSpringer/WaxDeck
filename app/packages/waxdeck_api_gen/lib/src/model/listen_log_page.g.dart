// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'listen_log_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ListenLogPage extends ListenLogPage {
  @override
  final BuiltList<ListenLogEntry> sessions;
  @override
  final String? nextCursor;

  factory _$ListenLogPage([void Function(ListenLogPageBuilder)? updates]) =>
      (ListenLogPageBuilder()..update(updates))._build();

  _$ListenLogPage._({required this.sessions, this.nextCursor}) : super._();
  @override
  ListenLogPage rebuild(void Function(ListenLogPageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ListenLogPageBuilder toBuilder() => ListenLogPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ListenLogPage &&
        sessions == other.sessions &&
        nextCursor == other.nextCursor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, sessions.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ListenLogPage')
          ..add('sessions', sessions)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class ListenLogPageBuilder
    implements Builder<ListenLogPage, ListenLogPageBuilder> {
  _$ListenLogPage? _$v;

  ListBuilder<ListenLogEntry>? _sessions;
  ListBuilder<ListenLogEntry> get sessions =>
      _$this._sessions ??= ListBuilder<ListenLogEntry>();
  set sessions(ListBuilder<ListenLogEntry>? sessions) =>
      _$this._sessions = sessions;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  ListenLogPageBuilder() {
    ListenLogPage._defaults(this);
  }

  ListenLogPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sessions = $v.sessions.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ListenLogPage other) {
    _$v = other as _$ListenLogPage;
  }

  @override
  void update(void Function(ListenLogPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ListenLogPage build() => _build();

  _$ListenLogPage _build() {
    _$ListenLogPage _$result;
    try {
      _$result =
          _$v ??
          _$ListenLogPage._(sessions: sessions.build(), nextCursor: nextCursor);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'sessions';
        sessions.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ListenLogPage',
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
