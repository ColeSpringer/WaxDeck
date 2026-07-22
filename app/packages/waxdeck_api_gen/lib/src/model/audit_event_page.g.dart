// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audit_event_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AuditEventPage extends AuditEventPage {
  @override
  final BuiltList<AuditEvent> events;
  @override
  final String? nextCursor;

  factory _$AuditEventPage([void Function(AuditEventPageBuilder)? updates]) =>
      (AuditEventPageBuilder()..update(updates))._build();

  _$AuditEventPage._({required this.events, this.nextCursor}) : super._();
  @override
  AuditEventPage rebuild(void Function(AuditEventPageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AuditEventPageBuilder toBuilder() => AuditEventPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AuditEventPage &&
        events == other.events &&
        nextCursor == other.nextCursor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, events.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AuditEventPage')
          ..add('events', events)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class AuditEventPageBuilder
    implements Builder<AuditEventPage, AuditEventPageBuilder> {
  _$AuditEventPage? _$v;

  ListBuilder<AuditEvent>? _events;
  ListBuilder<AuditEvent> get events =>
      _$this._events ??= ListBuilder<AuditEvent>();
  set events(ListBuilder<AuditEvent>? events) => _$this._events = events;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  AuditEventPageBuilder() {
    AuditEventPage._defaults(this);
  }

  AuditEventPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _events = $v.events.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AuditEventPage other) {
    _$v = other as _$AuditEventPage;
  }

  @override
  void update(void Function(AuditEventPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AuditEventPage build() => _build();

  _$AuditEventPage _build() {
    _$AuditEventPage _$result;
    try {
      _$result =
          _$v ??
          _$AuditEventPage._(events: events.build(), nextCursor: nextCursor);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'events';
        events.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'AuditEventPage',
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
