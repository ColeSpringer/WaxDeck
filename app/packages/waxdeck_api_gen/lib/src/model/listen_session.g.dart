// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'listen_session.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ListenSessionSource_Enum _$listenSessionSourceEnum_live =
    const ListenSessionSource_Enum._('live');
const ListenSessionSource_Enum _$listenSessionSourceEnum_import_ =
    const ListenSessionSource_Enum._('import_');

ListenSessionSource_Enum _$listenSessionSourceEnumValueOf(String name) {
  switch (name) {
    case 'live':
      return _$listenSessionSourceEnum_live;
    case 'import_':
      return _$listenSessionSourceEnum_import_;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ListenSessionSource_Enum> _$listenSessionSourceEnumValues =
    BuiltSet<ListenSessionSource_Enum>(const <ListenSessionSource_Enum>[
      _$listenSessionSourceEnum_live,
      _$listenSessionSourceEnum_import_,
    ]);

Serializer<ListenSessionSource_Enum> _$listenSessionSourceEnumSerializer =
    _$ListenSessionSource_EnumSerializer();

class _$ListenSessionSource_EnumSerializer
    implements PrimitiveSerializer<ListenSessionSource_Enum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'live': 'live',
    'import_': 'import',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'live': 'live',
    'import': 'import_',
  };

  @override
  final Iterable<Type> types = const <Type>[ListenSessionSource_Enum];
  @override
  final String wireName = 'ListenSessionSource_Enum';

  @override
  Object serialize(
    Serializers serializers,
    ListenSessionSource_Enum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  ListenSessionSource_Enum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => ListenSessionSource_Enum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$ListenSession extends ListenSession {
  @override
  final String sessionId;
  @override
  final String pid;
  @override
  final DateTime startedAt;
  @override
  final int msPlayed;
  @override
  final int? skippedMs;
  @override
  final bool? finished;
  @override
  final String? client;
  @override
  final ListenSessionSource_Enum? source_;

  factory _$ListenSession([void Function(ListenSessionBuilder)? updates]) =>
      (ListenSessionBuilder()..update(updates))._build();

  _$ListenSession._({
    required this.sessionId,
    required this.pid,
    required this.startedAt,
    required this.msPlayed,
    this.skippedMs,
    this.finished,
    this.client,
    this.source_,
  }) : super._();
  @override
  ListenSession rebuild(void Function(ListenSessionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ListenSessionBuilder toBuilder() => ListenSessionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ListenSession &&
        sessionId == other.sessionId &&
        pid == other.pid &&
        startedAt == other.startedAt &&
        msPlayed == other.msPlayed &&
        skippedMs == other.skippedMs &&
        finished == other.finished &&
        client == other.client &&
        source_ == other.source_;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, sessionId.hashCode);
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, startedAt.hashCode);
    _$hash = $jc(_$hash, msPlayed.hashCode);
    _$hash = $jc(_$hash, skippedMs.hashCode);
    _$hash = $jc(_$hash, finished.hashCode);
    _$hash = $jc(_$hash, client.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ListenSession')
          ..add('sessionId', sessionId)
          ..add('pid', pid)
          ..add('startedAt', startedAt)
          ..add('msPlayed', msPlayed)
          ..add('skippedMs', skippedMs)
          ..add('finished', finished)
          ..add('client', client)
          ..add('source_', source_))
        .toString();
  }
}

class ListenSessionBuilder
    implements Builder<ListenSession, ListenSessionBuilder> {
  _$ListenSession? _$v;

  String? _sessionId;
  String? get sessionId => _$this._sessionId;
  set sessionId(String? sessionId) => _$this._sessionId = sessionId;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  DateTime? _startedAt;
  DateTime? get startedAt => _$this._startedAt;
  set startedAt(DateTime? startedAt) => _$this._startedAt = startedAt;

  int? _msPlayed;
  int? get msPlayed => _$this._msPlayed;
  set msPlayed(int? msPlayed) => _$this._msPlayed = msPlayed;

  int? _skippedMs;
  int? get skippedMs => _$this._skippedMs;
  set skippedMs(int? skippedMs) => _$this._skippedMs = skippedMs;

  bool? _finished;
  bool? get finished => _$this._finished;
  set finished(bool? finished) => _$this._finished = finished;

  String? _client;
  String? get client => _$this._client;
  set client(String? client) => _$this._client = client;

  ListenSessionSource_Enum? _source_;
  ListenSessionSource_Enum? get source_ => _$this._source_;
  set source_(ListenSessionSource_Enum? source_) => _$this._source_ = source_;

  ListenSessionBuilder() {
    ListenSession._defaults(this);
  }

  ListenSessionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sessionId = $v.sessionId;
      _pid = $v.pid;
      _startedAt = $v.startedAt;
      _msPlayed = $v.msPlayed;
      _skippedMs = $v.skippedMs;
      _finished = $v.finished;
      _client = $v.client;
      _source_ = $v.source_;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ListenSession other) {
    _$v = other as _$ListenSession;
  }

  @override
  void update(void Function(ListenSessionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ListenSession build() => _build();

  _$ListenSession _build() {
    final _$result =
        _$v ??
        _$ListenSession._(
          sessionId: BuiltValueNullFieldError.checkNotNull(
            sessionId,
            r'ListenSession',
            'sessionId',
          ),
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'ListenSession',
            'pid',
          ),
          startedAt: BuiltValueNullFieldError.checkNotNull(
            startedAt,
            r'ListenSession',
            'startedAt',
          ),
          msPlayed: BuiltValueNullFieldError.checkNotNull(
            msPlayed,
            r'ListenSession',
            'msPlayed',
          ),
          skippedMs: skippedMs,
          finished: finished,
          client: client,
          source_: source_,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
