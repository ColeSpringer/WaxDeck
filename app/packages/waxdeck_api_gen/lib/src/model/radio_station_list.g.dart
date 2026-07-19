// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'radio_station_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RadioStationList extends RadioStationList {
  @override
  final BuiltList<RadioStation> stations;

  factory _$RadioStationList([
    void Function(RadioStationListBuilder)? updates,
  ]) => (RadioStationListBuilder()..update(updates))._build();

  _$RadioStationList._({required this.stations}) : super._();
  @override
  RadioStationList rebuild(void Function(RadioStationListBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RadioStationListBuilder toBuilder() =>
      RadioStationListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RadioStationList && stations == other.stations;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, stations.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'RadioStationList',
    )..add('stations', stations)).toString();
  }
}

class RadioStationListBuilder
    implements Builder<RadioStationList, RadioStationListBuilder> {
  _$RadioStationList? _$v;

  ListBuilder<RadioStation>? _stations;
  ListBuilder<RadioStation> get stations =>
      _$this._stations ??= ListBuilder<RadioStation>();
  set stations(ListBuilder<RadioStation>? stations) =>
      _$this._stations = stations;

  RadioStationListBuilder() {
    RadioStationList._defaults(this);
  }

  RadioStationListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _stations = $v.stations.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RadioStationList other) {
    _$v = other as _$RadioStationList;
  }

  @override
  void update(void Function(RadioStationListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RadioStationList build() => _build();

  _$RadioStationList _build() {
    _$RadioStationList _$result;
    try {
      _$result = _$v ?? _$RadioStationList._(stations: stations.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'stations';
        stations.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'RadioStationList',
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
