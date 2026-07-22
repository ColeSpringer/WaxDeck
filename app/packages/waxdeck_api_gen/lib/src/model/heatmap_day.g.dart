// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'heatmap_day.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$HeatmapDay extends HeatmapDay {
  @override
  final Date date;
  @override
  final int ms;
  @override
  final int sessions;

  factory _$HeatmapDay([void Function(HeatmapDayBuilder)? updates]) =>
      (HeatmapDayBuilder()..update(updates))._build();

  _$HeatmapDay._({required this.date, required this.ms, required this.sessions})
    : super._();
  @override
  HeatmapDay rebuild(void Function(HeatmapDayBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HeatmapDayBuilder toBuilder() => HeatmapDayBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HeatmapDay &&
        date == other.date &&
        ms == other.ms &&
        sessions == other.sessions;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, ms.hashCode);
    _$hash = $jc(_$hash, sessions.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HeatmapDay')
          ..add('date', date)
          ..add('ms', ms)
          ..add('sessions', sessions))
        .toString();
  }
}

class HeatmapDayBuilder implements Builder<HeatmapDay, HeatmapDayBuilder> {
  _$HeatmapDay? _$v;

  Date? _date;
  Date? get date => _$this._date;
  set date(Date? date) => _$this._date = date;

  int? _ms;
  int? get ms => _$this._ms;
  set ms(int? ms) => _$this._ms = ms;

  int? _sessions;
  int? get sessions => _$this._sessions;
  set sessions(int? sessions) => _$this._sessions = sessions;

  HeatmapDayBuilder() {
    HeatmapDay._defaults(this);
  }

  HeatmapDayBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _date = $v.date;
      _ms = $v.ms;
      _sessions = $v.sessions;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HeatmapDay other) {
    _$v = other as _$HeatmapDay;
  }

  @override
  void update(void Function(HeatmapDayBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HeatmapDay build() => _build();

  _$HeatmapDay _build() {
    final _$result =
        _$v ??
        _$HeatmapDay._(
          date: BuiltValueNullFieldError.checkNotNull(
            date,
            r'HeatmapDay',
            'date',
          ),
          ms: BuiltValueNullFieldError.checkNotNull(ms, r'HeatmapDay', 'ms'),
          sessions: BuiltValueNullFieldError.checkNotNull(
            sessions,
            r'HeatmapDay',
            'sessions',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
