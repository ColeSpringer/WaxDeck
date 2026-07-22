// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'month_listening.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MonthListening extends MonthListening {
  @override
  final int month;
  @override
  final int ms;
  @override
  final int sessions;

  factory _$MonthListening([void Function(MonthListeningBuilder)? updates]) =>
      (MonthListeningBuilder()..update(updates))._build();

  _$MonthListening._({
    required this.month,
    required this.ms,
    required this.sessions,
  }) : super._();
  @override
  MonthListening rebuild(void Function(MonthListeningBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MonthListeningBuilder toBuilder() => MonthListeningBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MonthListening &&
        month == other.month &&
        ms == other.ms &&
        sessions == other.sessions;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, month.hashCode);
    _$hash = $jc(_$hash, ms.hashCode);
    _$hash = $jc(_$hash, sessions.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MonthListening')
          ..add('month', month)
          ..add('ms', ms)
          ..add('sessions', sessions))
        .toString();
  }
}

class MonthListeningBuilder
    implements Builder<MonthListening, MonthListeningBuilder> {
  _$MonthListening? _$v;

  int? _month;
  int? get month => _$this._month;
  set month(int? month) => _$this._month = month;

  int? _ms;
  int? get ms => _$this._ms;
  set ms(int? ms) => _$this._ms = ms;

  int? _sessions;
  int? get sessions => _$this._sessions;
  set sessions(int? sessions) => _$this._sessions = sessions;

  MonthListeningBuilder() {
    MonthListening._defaults(this);
  }

  MonthListeningBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _month = $v.month;
      _ms = $v.ms;
      _sessions = $v.sessions;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MonthListening other) {
    _$v = other as _$MonthListening;
  }

  @override
  void update(void Function(MonthListeningBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MonthListening build() => _build();

  _$MonthListening _build() {
    final _$result =
        _$v ??
        _$MonthListening._(
          month: BuiltValueNullFieldError.checkNotNull(
            month,
            r'MonthListening',
            'month',
          ),
          ms: BuiltValueNullFieldError.checkNotNull(
            ms,
            r'MonthListening',
            'ms',
          ),
          sessions: BuiltValueNullFieldError.checkNotNull(
            sessions,
            r'MonthListening',
            'sessions',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
