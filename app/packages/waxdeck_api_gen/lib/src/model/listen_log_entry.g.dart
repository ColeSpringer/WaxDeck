// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'listen_log_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ListenLogEntrySource_Enum _$listenLogEntrySourceEnum_live =
    const ListenLogEntrySource_Enum._('live');
const ListenLogEntrySource_Enum _$listenLogEntrySourceEnum_import_ =
    const ListenLogEntrySource_Enum._('import_');
const ListenLogEntrySource_Enum
_$listenLogEntrySourceEnum_unknownDefaultOpenApi =
    const ListenLogEntrySource_Enum._('unknownDefaultOpenApi');

ListenLogEntrySource_Enum _$listenLogEntrySourceEnumValueOf(String name) {
  switch (name) {
    case 'live':
      return _$listenLogEntrySourceEnum_live;
    case 'import_':
      return _$listenLogEntrySourceEnum_import_;
    case 'unknownDefaultOpenApi':
      return _$listenLogEntrySourceEnum_unknownDefaultOpenApi;
    default:
      return _$listenLogEntrySourceEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<ListenLogEntrySource_Enum> _$listenLogEntrySourceEnumValues =
    BuiltSet<ListenLogEntrySource_Enum>(const <ListenLogEntrySource_Enum>[
      _$listenLogEntrySourceEnum_live,
      _$listenLogEntrySourceEnum_import_,
      _$listenLogEntrySourceEnum_unknownDefaultOpenApi,
    ]);

Serializer<ListenLogEntrySource_Enum> _$listenLogEntrySourceEnumSerializer =
    _$ListenLogEntrySource_EnumSerializer();

class _$ListenLogEntrySource_EnumSerializer
    implements PrimitiveSerializer<ListenLogEntrySource_Enum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'live': 'live',
    'import_': 'import',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'live': 'live',
    'import': 'import_',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[ListenLogEntrySource_Enum];
  @override
  final String wireName = 'ListenLogEntrySource_Enum';

  @override
  Object serialize(
    Serializers serializers,
    ListenLogEntrySource_Enum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  ListenLogEntrySource_Enum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => ListenLogEntrySource_Enum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$ListenLogEntry extends ListenLogEntry {
  @override
  final String pid;
  @override
  final String? title;
  @override
  final String? artist;
  @override
  final MediaType mediaType;
  @override
  final DateTime startedAt;
  @override
  final int msPlayed;
  @override
  final int? skippedMs;
  @override
  final bool finished;
  @override
  final String client;
  @override
  final ListenLogEntrySource_Enum source_;

  factory _$ListenLogEntry([void Function(ListenLogEntryBuilder)? updates]) =>
      (ListenLogEntryBuilder()..update(updates))._build();

  _$ListenLogEntry._({
    required this.pid,
    this.title,
    this.artist,
    required this.mediaType,
    required this.startedAt,
    required this.msPlayed,
    this.skippedMs,
    required this.finished,
    required this.client,
    required this.source_,
  }) : super._();
  @override
  ListenLogEntry rebuild(void Function(ListenLogEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ListenLogEntryBuilder toBuilder() => ListenLogEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ListenLogEntry &&
        pid == other.pid &&
        title == other.title &&
        artist == other.artist &&
        mediaType == other.mediaType &&
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
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, artist.hashCode);
    _$hash = $jc(_$hash, mediaType.hashCode);
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
    return (newBuiltValueToStringHelper(r'ListenLogEntry')
          ..add('pid', pid)
          ..add('title', title)
          ..add('artist', artist)
          ..add('mediaType', mediaType)
          ..add('startedAt', startedAt)
          ..add('msPlayed', msPlayed)
          ..add('skippedMs', skippedMs)
          ..add('finished', finished)
          ..add('client', client)
          ..add('source_', source_))
        .toString();
  }
}

class ListenLogEntryBuilder
    implements Builder<ListenLogEntry, ListenLogEntryBuilder> {
  _$ListenLogEntry? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _artist;
  String? get artist => _$this._artist;
  set artist(String? artist) => _$this._artist = artist;

  MediaType? _mediaType;
  MediaType? get mediaType => _$this._mediaType;
  set mediaType(MediaType? mediaType) => _$this._mediaType = mediaType;

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

  ListenLogEntrySource_Enum? _source_;
  ListenLogEntrySource_Enum? get source_ => _$this._source_;
  set source_(ListenLogEntrySource_Enum? source_) => _$this._source_ = source_;

  ListenLogEntryBuilder() {
    ListenLogEntry._defaults(this);
  }

  ListenLogEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _title = $v.title;
      _artist = $v.artist;
      _mediaType = $v.mediaType;
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
  void replace(ListenLogEntry other) {
    _$v = other as _$ListenLogEntry;
  }

  @override
  void update(void Function(ListenLogEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ListenLogEntry build() => _build();

  _$ListenLogEntry _build() {
    final _$result =
        _$v ??
        _$ListenLogEntry._(
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'ListenLogEntry',
            'pid',
          ),
          title: title,
          artist: artist,
          mediaType: BuiltValueNullFieldError.checkNotNull(
            mediaType,
            r'ListenLogEntry',
            'mediaType',
          ),
          startedAt: BuiltValueNullFieldError.checkNotNull(
            startedAt,
            r'ListenLogEntry',
            'startedAt',
          ),
          msPlayed: BuiltValueNullFieldError.checkNotNull(
            msPlayed,
            r'ListenLogEntry',
            'msPlayed',
          ),
          skippedMs: skippedMs,
          finished: BuiltValueNullFieldError.checkNotNull(
            finished,
            r'ListenLogEntry',
            'finished',
          ),
          client: BuiltValueNullFieldError.checkNotNull(
            client,
            r'ListenLogEntry',
            'client',
          ),
          source_: BuiltValueNullFieldError.checkNotNull(
            source_,
            r'ListenLogEntry',
            'source_',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
