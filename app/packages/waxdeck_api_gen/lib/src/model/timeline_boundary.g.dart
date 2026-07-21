// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timeline_boundary.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TimelineBoundary extends TimelineBoundary {
  @override
  final String pid;
  @override
  final int offsetSamples;
  @override
  final int durationSamples;

  factory _$TimelineBoundary([
    void Function(TimelineBoundaryBuilder)? updates,
  ]) => (TimelineBoundaryBuilder()..update(updates))._build();

  _$TimelineBoundary._({
    required this.pid,
    required this.offsetSamples,
    required this.durationSamples,
  }) : super._();
  @override
  TimelineBoundary rebuild(void Function(TimelineBoundaryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TimelineBoundaryBuilder toBuilder() =>
      TimelineBoundaryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TimelineBoundary &&
        pid == other.pid &&
        offsetSamples == other.offsetSamples &&
        durationSamples == other.durationSamples;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, offsetSamples.hashCode);
    _$hash = $jc(_$hash, durationSamples.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TimelineBoundary')
          ..add('pid', pid)
          ..add('offsetSamples', offsetSamples)
          ..add('durationSamples', durationSamples))
        .toString();
  }
}

class TimelineBoundaryBuilder
    implements Builder<TimelineBoundary, TimelineBoundaryBuilder> {
  _$TimelineBoundary? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  int? _offsetSamples;
  int? get offsetSamples => _$this._offsetSamples;
  set offsetSamples(int? offsetSamples) =>
      _$this._offsetSamples = offsetSamples;

  int? _durationSamples;
  int? get durationSamples => _$this._durationSamples;
  set durationSamples(int? durationSamples) =>
      _$this._durationSamples = durationSamples;

  TimelineBoundaryBuilder() {
    TimelineBoundary._defaults(this);
  }

  TimelineBoundaryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _offsetSamples = $v.offsetSamples;
      _durationSamples = $v.durationSamples;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TimelineBoundary other) {
    _$v = other as _$TimelineBoundary;
  }

  @override
  void update(void Function(TimelineBoundaryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TimelineBoundary build() => _build();

  _$TimelineBoundary _build() {
    final _$result =
        _$v ??
        _$TimelineBoundary._(
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'TimelineBoundary',
            'pid',
          ),
          offsetSamples: BuiltValueNullFieldError.checkNotNull(
            offsetSamples,
            r'TimelineBoundary',
            'offsetSamples',
          ),
          durationSamples: BuiltValueNullFieldError.checkNotNull(
            durationSamples,
            r'TimelineBoundary',
            'durationSamples',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
