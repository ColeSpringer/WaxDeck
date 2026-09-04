// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timeline_create.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TimelineCreate extends TimelineCreate {
  @override
  final BuiltList<String> itemPids;
  @override
  final double? crossfadeSeconds;
  @override
  final BuiltList<TimelineFormat>? formats;

  factory _$TimelineCreate([void Function(TimelineCreateBuilder)? updates]) =>
      (TimelineCreateBuilder()..update(updates))._build();

  _$TimelineCreate._({
    required this.itemPids,
    this.crossfadeSeconds,
    this.formats,
  }) : super._();
  @override
  TimelineCreate rebuild(void Function(TimelineCreateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TimelineCreateBuilder toBuilder() => TimelineCreateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TimelineCreate &&
        itemPids == other.itemPids &&
        crossfadeSeconds == other.crossfadeSeconds &&
        formats == other.formats;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, itemPids.hashCode);
    _$hash = $jc(_$hash, crossfadeSeconds.hashCode);
    _$hash = $jc(_$hash, formats.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TimelineCreate')
          ..add('itemPids', itemPids)
          ..add('crossfadeSeconds', crossfadeSeconds)
          ..add('formats', formats))
        .toString();
  }
}

class TimelineCreateBuilder
    implements Builder<TimelineCreate, TimelineCreateBuilder> {
  _$TimelineCreate? _$v;

  ListBuilder<String>? _itemPids;
  ListBuilder<String> get itemPids =>
      _$this._itemPids ??= ListBuilder<String>();
  set itemPids(ListBuilder<String>? itemPids) => _$this._itemPids = itemPids;

  double? _crossfadeSeconds;
  double? get crossfadeSeconds => _$this._crossfadeSeconds;
  set crossfadeSeconds(double? crossfadeSeconds) =>
      _$this._crossfadeSeconds = crossfadeSeconds;

  ListBuilder<TimelineFormat>? _formats;
  ListBuilder<TimelineFormat> get formats =>
      _$this._formats ??= ListBuilder<TimelineFormat>();
  set formats(ListBuilder<TimelineFormat>? formats) =>
      _$this._formats = formats;

  TimelineCreateBuilder() {
    TimelineCreate._defaults(this);
  }

  TimelineCreateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _itemPids = $v.itemPids.toBuilder();
      _crossfadeSeconds = $v.crossfadeSeconds;
      _formats = $v.formats?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TimelineCreate other) {
    _$v = other as _$TimelineCreate;
  }

  @override
  void update(void Function(TimelineCreateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TimelineCreate build() => _build();

  _$TimelineCreate _build() {
    _$TimelineCreate _$result;
    try {
      _$result =
          _$v ??
          _$TimelineCreate._(
            itemPids: itemPids.build(),
            crossfadeSeconds: crossfadeSeconds,
            formats: _formats?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'itemPids';
        itemPids.build();

        _$failedField = 'formats';
        _formats?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'TimelineCreate',
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
