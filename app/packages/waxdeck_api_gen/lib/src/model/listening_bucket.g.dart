// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'listening_bucket.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ListeningBucket extends ListeningBucket {
  @override
  final Date start;
  @override
  final int ms;
  @override
  final int sessions;

  factory _$ListeningBucket([void Function(ListeningBucketBuilder)? updates]) =>
      (ListeningBucketBuilder()..update(updates))._build();

  _$ListeningBucket._({
    required this.start,
    required this.ms,
    required this.sessions,
  }) : super._();
  @override
  ListeningBucket rebuild(void Function(ListeningBucketBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ListeningBucketBuilder toBuilder() => ListeningBucketBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ListeningBucket &&
        start == other.start &&
        ms == other.ms &&
        sessions == other.sessions;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, start.hashCode);
    _$hash = $jc(_$hash, ms.hashCode);
    _$hash = $jc(_$hash, sessions.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ListeningBucket')
          ..add('start', start)
          ..add('ms', ms)
          ..add('sessions', sessions))
        .toString();
  }
}

class ListeningBucketBuilder
    implements Builder<ListeningBucket, ListeningBucketBuilder> {
  _$ListeningBucket? _$v;

  Date? _start;
  Date? get start => _$this._start;
  set start(Date? start) => _$this._start = start;

  int? _ms;
  int? get ms => _$this._ms;
  set ms(int? ms) => _$this._ms = ms;

  int? _sessions;
  int? get sessions => _$this._sessions;
  set sessions(int? sessions) => _$this._sessions = sessions;

  ListeningBucketBuilder() {
    ListeningBucket._defaults(this);
  }

  ListeningBucketBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _start = $v.start;
      _ms = $v.ms;
      _sessions = $v.sessions;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ListeningBucket other) {
    _$v = other as _$ListeningBucket;
  }

  @override
  void update(void Function(ListeningBucketBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ListeningBucket build() => _build();

  _$ListeningBucket _build() {
    final _$result =
        _$v ??
        _$ListeningBucket._(
          start: BuiltValueNullFieldError.checkNotNull(
            start,
            r'ListeningBucket',
            'start',
          ),
          ms: BuiltValueNullFieldError.checkNotNull(
            ms,
            r'ListeningBucket',
            'ms',
          ),
          sessions: BuiltValueNullFieldError.checkNotNull(
            sessions,
            r'ListeningBucket',
            'sessions',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
