// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'listening_stats.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ListeningStatsRangeEnum _$listeningStatsRangeEnum_n7d =
    const ListeningStatsRangeEnum._('n7d');
const ListeningStatsRangeEnum _$listeningStatsRangeEnum_n30d =
    const ListeningStatsRangeEnum._('n30d');
const ListeningStatsRangeEnum _$listeningStatsRangeEnum_n90d =
    const ListeningStatsRangeEnum._('n90d');
const ListeningStatsRangeEnum _$listeningStatsRangeEnum_n365d =
    const ListeningStatsRangeEnum._('n365d');
const ListeningStatsRangeEnum _$listeningStatsRangeEnum_all =
    const ListeningStatsRangeEnum._('all');
const ListeningStatsRangeEnum _$listeningStatsRangeEnum_unknownDefaultOpenApi =
    const ListeningStatsRangeEnum._('unknownDefaultOpenApi');

ListeningStatsRangeEnum _$listeningStatsRangeEnumValueOf(String name) {
  switch (name) {
    case 'n7d':
      return _$listeningStatsRangeEnum_n7d;
    case 'n30d':
      return _$listeningStatsRangeEnum_n30d;
    case 'n90d':
      return _$listeningStatsRangeEnum_n90d;
    case 'n365d':
      return _$listeningStatsRangeEnum_n365d;
    case 'all':
      return _$listeningStatsRangeEnum_all;
    case 'unknownDefaultOpenApi':
      return _$listeningStatsRangeEnum_unknownDefaultOpenApi;
    default:
      return _$listeningStatsRangeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<ListeningStatsRangeEnum> _$listeningStatsRangeEnumValues =
    BuiltSet<ListeningStatsRangeEnum>(const <ListeningStatsRangeEnum>[
      _$listeningStatsRangeEnum_n7d,
      _$listeningStatsRangeEnum_n30d,
      _$listeningStatsRangeEnum_n90d,
      _$listeningStatsRangeEnum_n365d,
      _$listeningStatsRangeEnum_all,
      _$listeningStatsRangeEnum_unknownDefaultOpenApi,
    ]);

const ListeningStatsBucketEnum _$listeningStatsBucketEnum_day =
    const ListeningStatsBucketEnum._('day');
const ListeningStatsBucketEnum _$listeningStatsBucketEnum_week =
    const ListeningStatsBucketEnum._('week');
const ListeningStatsBucketEnum _$listeningStatsBucketEnum_month =
    const ListeningStatsBucketEnum._('month');
const ListeningStatsBucketEnum
_$listeningStatsBucketEnum_unknownDefaultOpenApi =
    const ListeningStatsBucketEnum._('unknownDefaultOpenApi');

ListeningStatsBucketEnum _$listeningStatsBucketEnumValueOf(String name) {
  switch (name) {
    case 'day':
      return _$listeningStatsBucketEnum_day;
    case 'week':
      return _$listeningStatsBucketEnum_week;
    case 'month':
      return _$listeningStatsBucketEnum_month;
    case 'unknownDefaultOpenApi':
      return _$listeningStatsBucketEnum_unknownDefaultOpenApi;
    default:
      return _$listeningStatsBucketEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<ListeningStatsBucketEnum> _$listeningStatsBucketEnumValues =
    BuiltSet<ListeningStatsBucketEnum>(const <ListeningStatsBucketEnum>[
      _$listeningStatsBucketEnum_day,
      _$listeningStatsBucketEnum_week,
      _$listeningStatsBucketEnum_month,
      _$listeningStatsBucketEnum_unknownDefaultOpenApi,
    ]);

Serializer<ListeningStatsRangeEnum> _$listeningStatsRangeEnumSerializer =
    _$ListeningStatsRangeEnumSerializer();
Serializer<ListeningStatsBucketEnum> _$listeningStatsBucketEnumSerializer =
    _$ListeningStatsBucketEnumSerializer();

class _$ListeningStatsRangeEnumSerializer
    implements PrimitiveSerializer<ListeningStatsRangeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'n7d': '7d',
    'n30d': '30d',
    'n90d': '90d',
    'n365d': '365d',
    'all': 'all',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    '7d': 'n7d',
    '30d': 'n30d',
    '90d': 'n90d',
    '365d': 'n365d',
    'all': 'all',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[ListeningStatsRangeEnum];
  @override
  final String wireName = 'ListeningStatsRangeEnum';

  @override
  Object serialize(
    Serializers serializers,
    ListeningStatsRangeEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  ListeningStatsRangeEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => ListeningStatsRangeEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$ListeningStatsBucketEnumSerializer
    implements PrimitiveSerializer<ListeningStatsBucketEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'day': 'day',
    'week': 'week',
    'month': 'month',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'day': 'day',
    'week': 'week',
    'month': 'month',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[ListeningStatsBucketEnum];
  @override
  final String wireName = 'ListeningStatsBucketEnum';

  @override
  Object serialize(
    Serializers serializers,
    ListeningStatsBucketEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  ListeningStatsBucketEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => ListeningStatsBucketEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$ListeningStats extends ListeningStats {
  @override
  final ListeningStatsRangeEnum range;
  @override
  final ListeningStatsBucketEnum bucket;
  @override
  final String timezone;
  @override
  final int totalMs;
  @override
  final int sessions;
  @override
  final int timeSavedMs;
  @override
  final BuiltList<ListeningBucket> buckets;
  @override
  final BuiltList<MediaTypeListening> byMediaType;

  factory _$ListeningStats([void Function(ListeningStatsBuilder)? updates]) =>
      (ListeningStatsBuilder()..update(updates))._build();

  _$ListeningStats._({
    required this.range,
    required this.bucket,
    required this.timezone,
    required this.totalMs,
    required this.sessions,
    required this.timeSavedMs,
    required this.buckets,
    required this.byMediaType,
  }) : super._();
  @override
  ListeningStats rebuild(void Function(ListeningStatsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ListeningStatsBuilder toBuilder() => ListeningStatsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ListeningStats &&
        range == other.range &&
        bucket == other.bucket &&
        timezone == other.timezone &&
        totalMs == other.totalMs &&
        sessions == other.sessions &&
        timeSavedMs == other.timeSavedMs &&
        buckets == other.buckets &&
        byMediaType == other.byMediaType;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, range.hashCode);
    _$hash = $jc(_$hash, bucket.hashCode);
    _$hash = $jc(_$hash, timezone.hashCode);
    _$hash = $jc(_$hash, totalMs.hashCode);
    _$hash = $jc(_$hash, sessions.hashCode);
    _$hash = $jc(_$hash, timeSavedMs.hashCode);
    _$hash = $jc(_$hash, buckets.hashCode);
    _$hash = $jc(_$hash, byMediaType.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ListeningStats')
          ..add('range', range)
          ..add('bucket', bucket)
          ..add('timezone', timezone)
          ..add('totalMs', totalMs)
          ..add('sessions', sessions)
          ..add('timeSavedMs', timeSavedMs)
          ..add('buckets', buckets)
          ..add('byMediaType', byMediaType))
        .toString();
  }
}

class ListeningStatsBuilder
    implements Builder<ListeningStats, ListeningStatsBuilder> {
  _$ListeningStats? _$v;

  ListeningStatsRangeEnum? _range;
  ListeningStatsRangeEnum? get range => _$this._range;
  set range(ListeningStatsRangeEnum? range) => _$this._range = range;

  ListeningStatsBucketEnum? _bucket;
  ListeningStatsBucketEnum? get bucket => _$this._bucket;
  set bucket(ListeningStatsBucketEnum? bucket) => _$this._bucket = bucket;

  String? _timezone;
  String? get timezone => _$this._timezone;
  set timezone(String? timezone) => _$this._timezone = timezone;

  int? _totalMs;
  int? get totalMs => _$this._totalMs;
  set totalMs(int? totalMs) => _$this._totalMs = totalMs;

  int? _sessions;
  int? get sessions => _$this._sessions;
  set sessions(int? sessions) => _$this._sessions = sessions;

  int? _timeSavedMs;
  int? get timeSavedMs => _$this._timeSavedMs;
  set timeSavedMs(int? timeSavedMs) => _$this._timeSavedMs = timeSavedMs;

  ListBuilder<ListeningBucket>? _buckets;
  ListBuilder<ListeningBucket> get buckets =>
      _$this._buckets ??= ListBuilder<ListeningBucket>();
  set buckets(ListBuilder<ListeningBucket>? buckets) =>
      _$this._buckets = buckets;

  ListBuilder<MediaTypeListening>? _byMediaType;
  ListBuilder<MediaTypeListening> get byMediaType =>
      _$this._byMediaType ??= ListBuilder<MediaTypeListening>();
  set byMediaType(ListBuilder<MediaTypeListening>? byMediaType) =>
      _$this._byMediaType = byMediaType;

  ListeningStatsBuilder() {
    ListeningStats._defaults(this);
  }

  ListeningStatsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _range = $v.range;
      _bucket = $v.bucket;
      _timezone = $v.timezone;
      _totalMs = $v.totalMs;
      _sessions = $v.sessions;
      _timeSavedMs = $v.timeSavedMs;
      _buckets = $v.buckets.toBuilder();
      _byMediaType = $v.byMediaType.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ListeningStats other) {
    _$v = other as _$ListeningStats;
  }

  @override
  void update(void Function(ListeningStatsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ListeningStats build() => _build();

  _$ListeningStats _build() {
    _$ListeningStats _$result;
    try {
      _$result =
          _$v ??
          _$ListeningStats._(
            range: BuiltValueNullFieldError.checkNotNull(
              range,
              r'ListeningStats',
              'range',
            ),
            bucket: BuiltValueNullFieldError.checkNotNull(
              bucket,
              r'ListeningStats',
              'bucket',
            ),
            timezone: BuiltValueNullFieldError.checkNotNull(
              timezone,
              r'ListeningStats',
              'timezone',
            ),
            totalMs: BuiltValueNullFieldError.checkNotNull(
              totalMs,
              r'ListeningStats',
              'totalMs',
            ),
            sessions: BuiltValueNullFieldError.checkNotNull(
              sessions,
              r'ListeningStats',
              'sessions',
            ),
            timeSavedMs: BuiltValueNullFieldError.checkNotNull(
              timeSavedMs,
              r'ListeningStats',
              'timeSavedMs',
            ),
            buckets: buckets.build(),
            byMediaType: byMediaType.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'buckets';
        buckets.build();
        _$failedField = 'byMediaType';
        byMediaType.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ListeningStats',
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
