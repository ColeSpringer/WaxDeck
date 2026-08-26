// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_source_update.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const PlaylistSourceUpdateSource_Enum _$playlistSourceUpdateSourceEnum_spotify =
    const PlaylistSourceUpdateSource_Enum._('spotify');
const PlaylistSourceUpdateSource_Enum
_$playlistSourceUpdateSourceEnum_applemusic =
    const PlaylistSourceUpdateSource_Enum._('applemusic');
const PlaylistSourceUpdateSource_Enum _$playlistSourceUpdateSourceEnum_ytmusic =
    const PlaylistSourceUpdateSource_Enum._('ytmusic');
const PlaylistSourceUpdateSource_Enum _$playlistSourceUpdateSourceEnum_csv =
    const PlaylistSourceUpdateSource_Enum._('csv');
const PlaylistSourceUpdateSource_Enum _$playlistSourceUpdateSourceEnum_text =
    const PlaylistSourceUpdateSource_Enum._('text');
const PlaylistSourceUpdateSource_Enum
_$playlistSourceUpdateSourceEnum_portable =
    const PlaylistSourceUpdateSource_Enum._('portable');
const PlaylistSourceUpdateSource_Enum
_$playlistSourceUpdateSourceEnum_unknownDefaultOpenApi =
    const PlaylistSourceUpdateSource_Enum._('unknownDefaultOpenApi');

PlaylistSourceUpdateSource_Enum _$playlistSourceUpdateSourceEnumValueOf(
  String name,
) {
  switch (name) {
    case 'spotify':
      return _$playlistSourceUpdateSourceEnum_spotify;
    case 'applemusic':
      return _$playlistSourceUpdateSourceEnum_applemusic;
    case 'ytmusic':
      return _$playlistSourceUpdateSourceEnum_ytmusic;
    case 'csv':
      return _$playlistSourceUpdateSourceEnum_csv;
    case 'text':
      return _$playlistSourceUpdateSourceEnum_text;
    case 'portable':
      return _$playlistSourceUpdateSourceEnum_portable;
    case 'unknownDefaultOpenApi':
      return _$playlistSourceUpdateSourceEnum_unknownDefaultOpenApi;
    default:
      return _$playlistSourceUpdateSourceEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<PlaylistSourceUpdateSource_Enum>
_$playlistSourceUpdateSourceEnumValues =
    BuiltSet<PlaylistSourceUpdateSource_Enum>(
      const <PlaylistSourceUpdateSource_Enum>[
        _$playlistSourceUpdateSourceEnum_spotify,
        _$playlistSourceUpdateSourceEnum_applemusic,
        _$playlistSourceUpdateSourceEnum_ytmusic,
        _$playlistSourceUpdateSourceEnum_csv,
        _$playlistSourceUpdateSourceEnum_text,
        _$playlistSourceUpdateSourceEnum_portable,
        _$playlistSourceUpdateSourceEnum_unknownDefaultOpenApi,
      ],
    );

const PlaylistSourceUpdateModeEnum _$playlistSourceUpdateModeEnum_append =
    const PlaylistSourceUpdateModeEnum._('append');
const PlaylistSourceUpdateModeEnum _$playlistSourceUpdateModeEnum_mirror =
    const PlaylistSourceUpdateModeEnum._('mirror');
const PlaylistSourceUpdateModeEnum _$playlistSourceUpdateModeEnum_mirrorTrash =
    const PlaylistSourceUpdateModeEnum._('mirrorTrash');
const PlaylistSourceUpdateModeEnum
_$playlistSourceUpdateModeEnum_unknownDefaultOpenApi =
    const PlaylistSourceUpdateModeEnum._('unknownDefaultOpenApi');

PlaylistSourceUpdateModeEnum _$playlistSourceUpdateModeEnumValueOf(
  String name,
) {
  switch (name) {
    case 'append':
      return _$playlistSourceUpdateModeEnum_append;
    case 'mirror':
      return _$playlistSourceUpdateModeEnum_mirror;
    case 'mirrorTrash':
      return _$playlistSourceUpdateModeEnum_mirrorTrash;
    case 'unknownDefaultOpenApi':
      return _$playlistSourceUpdateModeEnum_unknownDefaultOpenApi;
    default:
      return _$playlistSourceUpdateModeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<PlaylistSourceUpdateModeEnum>
_$playlistSourceUpdateModeEnumValues =
    BuiltSet<PlaylistSourceUpdateModeEnum>(const <PlaylistSourceUpdateModeEnum>[
      _$playlistSourceUpdateModeEnum_append,
      _$playlistSourceUpdateModeEnum_mirror,
      _$playlistSourceUpdateModeEnum_mirrorTrash,
      _$playlistSourceUpdateModeEnum_unknownDefaultOpenApi,
    ]);

Serializer<PlaylistSourceUpdateSource_Enum>
_$playlistSourceUpdateSourceEnumSerializer =
    _$PlaylistSourceUpdateSource_EnumSerializer();
Serializer<PlaylistSourceUpdateModeEnum>
_$playlistSourceUpdateModeEnumSerializer =
    _$PlaylistSourceUpdateModeEnumSerializer();

class _$PlaylistSourceUpdateSource_EnumSerializer
    implements PrimitiveSerializer<PlaylistSourceUpdateSource_Enum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'spotify': 'spotify',
    'applemusic': 'applemusic',
    'ytmusic': 'ytmusic',
    'csv': 'csv',
    'text': 'text',
    'portable': 'portable',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'spotify': 'spotify',
    'applemusic': 'applemusic',
    'ytmusic': 'ytmusic',
    'csv': 'csv',
    'text': 'text',
    'portable': 'portable',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[PlaylistSourceUpdateSource_Enum];
  @override
  final String wireName = 'PlaylistSourceUpdateSource_Enum';

  @override
  Object serialize(
    Serializers serializers,
    PlaylistSourceUpdateSource_Enum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  PlaylistSourceUpdateSource_Enum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => PlaylistSourceUpdateSource_Enum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$PlaylistSourceUpdateModeEnumSerializer
    implements PrimitiveSerializer<PlaylistSourceUpdateModeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'append': 'append',
    'mirror': 'mirror',
    'mirrorTrash': 'mirror-trash',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'append': 'append',
    'mirror': 'mirror',
    'mirror-trash': 'mirrorTrash',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[PlaylistSourceUpdateModeEnum];
  @override
  final String wireName = 'PlaylistSourceUpdateModeEnum';

  @override
  Object serialize(
    Serializers serializers,
    PlaylistSourceUpdateModeEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  PlaylistSourceUpdateModeEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => PlaylistSourceUpdateModeEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$PlaylistSourceUpdate extends PlaylistSourceUpdate {
  @override
  final String? url;
  @override
  final PlaylistSourceUpdateSource_Enum? source_;
  @override
  final String? payload;
  @override
  final BuiltList<PortableRef>? refs;
  @override
  final PlaylistSourceUpdateModeEnum mode;
  @override
  final int? intervalHours;

  factory _$PlaylistSourceUpdate([
    void Function(PlaylistSourceUpdateBuilder)? updates,
  ]) => (PlaylistSourceUpdateBuilder()..update(updates))._build();

  _$PlaylistSourceUpdate._({
    this.url,
    this.source_,
    this.payload,
    this.refs,
    required this.mode,
    this.intervalHours,
  }) : super._();
  @override
  PlaylistSourceUpdate rebuild(
    void Function(PlaylistSourceUpdateBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PlaylistSourceUpdateBuilder toBuilder() =>
      PlaylistSourceUpdateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaylistSourceUpdate &&
        url == other.url &&
        source_ == other.source_ &&
        payload == other.payload &&
        refs == other.refs &&
        mode == other.mode &&
        intervalHours == other.intervalHours;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, payload.hashCode);
    _$hash = $jc(_$hash, refs.hashCode);
    _$hash = $jc(_$hash, mode.hashCode);
    _$hash = $jc(_$hash, intervalHours.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaylistSourceUpdate')
          ..add('url', url)
          ..add('source_', source_)
          ..add('payload', payload)
          ..add('refs', refs)
          ..add('mode', mode)
          ..add('intervalHours', intervalHours))
        .toString();
  }
}

class PlaylistSourceUpdateBuilder
    implements Builder<PlaylistSourceUpdate, PlaylistSourceUpdateBuilder> {
  _$PlaylistSourceUpdate? _$v;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  PlaylistSourceUpdateSource_Enum? _source_;
  PlaylistSourceUpdateSource_Enum? get source_ => _$this._source_;
  set source_(PlaylistSourceUpdateSource_Enum? source_) =>
      _$this._source_ = source_;

  String? _payload;
  String? get payload => _$this._payload;
  set payload(String? payload) => _$this._payload = payload;

  ListBuilder<PortableRef>? _refs;
  ListBuilder<PortableRef> get refs =>
      _$this._refs ??= ListBuilder<PortableRef>();
  set refs(ListBuilder<PortableRef>? refs) => _$this._refs = refs;

  PlaylistSourceUpdateModeEnum? _mode;
  PlaylistSourceUpdateModeEnum? get mode => _$this._mode;
  set mode(PlaylistSourceUpdateModeEnum? mode) => _$this._mode = mode;

  int? _intervalHours;
  int? get intervalHours => _$this._intervalHours;
  set intervalHours(int? intervalHours) =>
      _$this._intervalHours = intervalHours;

  PlaylistSourceUpdateBuilder() {
    PlaylistSourceUpdate._defaults(this);
  }

  PlaylistSourceUpdateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _url = $v.url;
      _source_ = $v.source_;
      _payload = $v.payload;
      _refs = $v.refs?.toBuilder();
      _mode = $v.mode;
      _intervalHours = $v.intervalHours;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaylistSourceUpdate other) {
    _$v = other as _$PlaylistSourceUpdate;
  }

  @override
  void update(void Function(PlaylistSourceUpdateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaylistSourceUpdate build() => _build();

  _$PlaylistSourceUpdate _build() {
    _$PlaylistSourceUpdate _$result;
    try {
      _$result =
          _$v ??
          _$PlaylistSourceUpdate._(
            url: url,
            source_: source_,
            payload: payload,
            refs: _refs?.build(),
            mode: BuiltValueNullFieldError.checkNotNull(
              mode,
              r'PlaylistSourceUpdate',
              'mode',
            ),
            intervalHours: intervalHours,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'refs';
        _refs?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlaylistSourceUpdate',
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
