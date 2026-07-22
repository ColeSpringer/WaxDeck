// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'listening_heatmap.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ListeningHeatmap extends ListeningHeatmap {
  @override
  final int year;
  @override
  final String timezone;
  @override
  final BuiltList<HeatmapDay> days;
  @override
  final int currentStreakDays;
  @override
  final int longestStreakDays;

  factory _$ListeningHeatmap([
    void Function(ListeningHeatmapBuilder)? updates,
  ]) => (ListeningHeatmapBuilder()..update(updates))._build();

  _$ListeningHeatmap._({
    required this.year,
    required this.timezone,
    required this.days,
    required this.currentStreakDays,
    required this.longestStreakDays,
  }) : super._();
  @override
  ListeningHeatmap rebuild(void Function(ListeningHeatmapBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ListeningHeatmapBuilder toBuilder() =>
      ListeningHeatmapBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ListeningHeatmap &&
        year == other.year &&
        timezone == other.timezone &&
        days == other.days &&
        currentStreakDays == other.currentStreakDays &&
        longestStreakDays == other.longestStreakDays;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, year.hashCode);
    _$hash = $jc(_$hash, timezone.hashCode);
    _$hash = $jc(_$hash, days.hashCode);
    _$hash = $jc(_$hash, currentStreakDays.hashCode);
    _$hash = $jc(_$hash, longestStreakDays.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ListeningHeatmap')
          ..add('year', year)
          ..add('timezone', timezone)
          ..add('days', days)
          ..add('currentStreakDays', currentStreakDays)
          ..add('longestStreakDays', longestStreakDays))
        .toString();
  }
}

class ListeningHeatmapBuilder
    implements Builder<ListeningHeatmap, ListeningHeatmapBuilder> {
  _$ListeningHeatmap? _$v;

  int? _year;
  int? get year => _$this._year;
  set year(int? year) => _$this._year = year;

  String? _timezone;
  String? get timezone => _$this._timezone;
  set timezone(String? timezone) => _$this._timezone = timezone;

  ListBuilder<HeatmapDay>? _days;
  ListBuilder<HeatmapDay> get days =>
      _$this._days ??= ListBuilder<HeatmapDay>();
  set days(ListBuilder<HeatmapDay>? days) => _$this._days = days;

  int? _currentStreakDays;
  int? get currentStreakDays => _$this._currentStreakDays;
  set currentStreakDays(int? currentStreakDays) =>
      _$this._currentStreakDays = currentStreakDays;

  int? _longestStreakDays;
  int? get longestStreakDays => _$this._longestStreakDays;
  set longestStreakDays(int? longestStreakDays) =>
      _$this._longestStreakDays = longestStreakDays;

  ListeningHeatmapBuilder() {
    ListeningHeatmap._defaults(this);
  }

  ListeningHeatmapBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _year = $v.year;
      _timezone = $v.timezone;
      _days = $v.days.toBuilder();
      _currentStreakDays = $v.currentStreakDays;
      _longestStreakDays = $v.longestStreakDays;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ListeningHeatmap other) {
    _$v = other as _$ListeningHeatmap;
  }

  @override
  void update(void Function(ListeningHeatmapBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ListeningHeatmap build() => _build();

  _$ListeningHeatmap _build() {
    _$ListeningHeatmap _$result;
    try {
      _$result =
          _$v ??
          _$ListeningHeatmap._(
            year: BuiltValueNullFieldError.checkNotNull(
              year,
              r'ListeningHeatmap',
              'year',
            ),
            timezone: BuiltValueNullFieldError.checkNotNull(
              timezone,
              r'ListeningHeatmap',
              'timezone',
            ),
            days: days.build(),
            currentStreakDays: BuiltValueNullFieldError.checkNotNull(
              currentStreakDays,
              r'ListeningHeatmap',
              'currentStreakDays',
            ),
            longestStreakDays: BuiltValueNullFieldError.checkNotNull(
              longestStreakDays,
              r'ListeningHeatmap',
              'longestStreakDays',
            ),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'days';
        days.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ListeningHeatmap',
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
