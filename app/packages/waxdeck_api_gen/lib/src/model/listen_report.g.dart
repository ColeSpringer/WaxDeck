// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'listen_report.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ListenReport extends ListenReport {
  @override
  final BuiltList<ListenSession> sessions;

  factory _$ListenReport([void Function(ListenReportBuilder)? updates]) =>
      (ListenReportBuilder()..update(updates))._build();

  _$ListenReport._({required this.sessions}) : super._();
  @override
  ListenReport rebuild(void Function(ListenReportBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ListenReportBuilder toBuilder() => ListenReportBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ListenReport && sessions == other.sessions;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, sessions.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'ListenReport',
    )..add('sessions', sessions)).toString();
  }
}

class ListenReportBuilder
    implements Builder<ListenReport, ListenReportBuilder> {
  _$ListenReport? _$v;

  ListBuilder<ListenSession>? _sessions;
  ListBuilder<ListenSession> get sessions =>
      _$this._sessions ??= ListBuilder<ListenSession>();
  set sessions(ListBuilder<ListenSession>? sessions) =>
      _$this._sessions = sessions;

  ListenReportBuilder() {
    ListenReport._defaults(this);
  }

  ListenReportBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sessions = $v.sessions.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ListenReport other) {
    _$v = other as _$ListenReport;
  }

  @override
  void update(void Function(ListenReportBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ListenReport build() => _build();

  _$ListenReport _build() {
    _$ListenReport _$result;
    try {
      _$result = _$v ?? _$ListenReport._(sessions: sessions.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'sessions';
        sessions.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ListenReport',
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
