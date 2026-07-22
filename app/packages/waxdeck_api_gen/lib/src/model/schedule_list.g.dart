// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schedule_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ScheduleList extends ScheduleList {
  @override
  final BuiltList<Schedule> schedules;

  factory _$ScheduleList([void Function(ScheduleListBuilder)? updates]) =>
      (ScheduleListBuilder()..update(updates))._build();

  _$ScheduleList._({required this.schedules}) : super._();
  @override
  ScheduleList rebuild(void Function(ScheduleListBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ScheduleListBuilder toBuilder() => ScheduleListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ScheduleList && schedules == other.schedules;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, schedules.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'ScheduleList',
    )..add('schedules', schedules)).toString();
  }
}

class ScheduleListBuilder
    implements Builder<ScheduleList, ScheduleListBuilder> {
  _$ScheduleList? _$v;

  ListBuilder<Schedule>? _schedules;
  ListBuilder<Schedule> get schedules =>
      _$this._schedules ??= ListBuilder<Schedule>();
  set schedules(ListBuilder<Schedule>? schedules) =>
      _$this._schedules = schedules;

  ScheduleListBuilder() {
    ScheduleList._defaults(this);
  }

  ScheduleListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _schedules = $v.schedules.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ScheduleList other) {
    _$v = other as _$ScheduleList;
  }

  @override
  void update(void Function(ScheduleListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ScheduleList build() => _build();

  _$ScheduleList _build() {
    _$ScheduleList _$result;
    try {
      _$result = _$v ?? _$ScheduleList._(schedules: schedules.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'schedules';
        schedules.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ScheduleList',
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
