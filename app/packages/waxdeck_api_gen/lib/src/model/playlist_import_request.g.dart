// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_import_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const PlaylistImportRequestSource_Enum
_$playlistImportRequestSourceEnum_spotify =
    const PlaylistImportRequestSource_Enum._('spotify');
const PlaylistImportRequestSource_Enum
_$playlistImportRequestSourceEnum_applemusic =
    const PlaylistImportRequestSource_Enum._('applemusic');
const PlaylistImportRequestSource_Enum
_$playlistImportRequestSourceEnum_ytmusic =
    const PlaylistImportRequestSource_Enum._('ytmusic');
const PlaylistImportRequestSource_Enum _$playlistImportRequestSourceEnum_csv =
    const PlaylistImportRequestSource_Enum._('csv');
const PlaylistImportRequestSource_Enum _$playlistImportRequestSourceEnum_text =
    const PlaylistImportRequestSource_Enum._('text');
const PlaylistImportRequestSource_Enum
_$playlistImportRequestSourceEnum_portable =
    const PlaylistImportRequestSource_Enum._('portable');
const PlaylistImportRequestSource_Enum
_$playlistImportRequestSourceEnum_unknownDefaultOpenApi =
    const PlaylistImportRequestSource_Enum._('unknownDefaultOpenApi');

PlaylistImportRequestSource_Enum _$playlistImportRequestSourceEnumValueOf(
  String name,
) {
  switch (name) {
    case 'spotify':
      return _$playlistImportRequestSourceEnum_spotify;
    case 'applemusic':
      return _$playlistImportRequestSourceEnum_applemusic;
    case 'ytmusic':
      return _$playlistImportRequestSourceEnum_ytmusic;
    case 'csv':
      return _$playlistImportRequestSourceEnum_csv;
    case 'text':
      return _$playlistImportRequestSourceEnum_text;
    case 'portable':
      return _$playlistImportRequestSourceEnum_portable;
    case 'unknownDefaultOpenApi':
      return _$playlistImportRequestSourceEnum_unknownDefaultOpenApi;
    default:
      return _$playlistImportRequestSourceEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<PlaylistImportRequestSource_Enum>
_$playlistImportRequestSourceEnumValues =
    BuiltSet<PlaylistImportRequestSource_Enum>(
      const <PlaylistImportRequestSource_Enum>[
        _$playlistImportRequestSourceEnum_spotify,
        _$playlistImportRequestSourceEnum_applemusic,
        _$playlistImportRequestSourceEnum_ytmusic,
        _$playlistImportRequestSourceEnum_csv,
        _$playlistImportRequestSourceEnum_text,
        _$playlistImportRequestSourceEnum_portable,
        _$playlistImportRequestSourceEnum_unknownDefaultOpenApi,
      ],
    );

Serializer<PlaylistImportRequestSource_Enum>
_$playlistImportRequestSourceEnumSerializer =
    _$PlaylistImportRequestSource_EnumSerializer();

class _$PlaylistImportRequestSource_EnumSerializer
    implements PrimitiveSerializer<PlaylistImportRequestSource_Enum> {
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
  final Iterable<Type> types = const <Type>[PlaylistImportRequestSource_Enum];
  @override
  final String wireName = 'PlaylistImportRequestSource_Enum';

  @override
  Object serialize(
    Serializers serializers,
    PlaylistImportRequestSource_Enum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  PlaylistImportRequestSource_Enum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => PlaylistImportRequestSource_Enum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$PlaylistImportRequest extends PlaylistImportRequest {
  @override
  final PlaylistImportRequestSource_Enum source_;
  @override
  final String? name;
  @override
  final String? payload;
  @override
  final BuiltList<PortableRef>? refs;

  factory _$PlaylistImportRequest([
    void Function(PlaylistImportRequestBuilder)? updates,
  ]) => (PlaylistImportRequestBuilder()..update(updates))._build();

  _$PlaylistImportRequest._({
    required this.source_,
    this.name,
    this.payload,
    this.refs,
  }) : super._();
  @override
  PlaylistImportRequest rebuild(
    void Function(PlaylistImportRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PlaylistImportRequestBuilder toBuilder() =>
      PlaylistImportRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaylistImportRequest &&
        source_ == other.source_ &&
        name == other.name &&
        payload == other.payload &&
        refs == other.refs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, payload.hashCode);
    _$hash = $jc(_$hash, refs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaylistImportRequest')
          ..add('source_', source_)
          ..add('name', name)
          ..add('payload', payload)
          ..add('refs', refs))
        .toString();
  }
}

class PlaylistImportRequestBuilder
    implements Builder<PlaylistImportRequest, PlaylistImportRequestBuilder> {
  _$PlaylistImportRequest? _$v;

  PlaylistImportRequestSource_Enum? _source_;
  PlaylistImportRequestSource_Enum? get source_ => _$this._source_;
  set source_(PlaylistImportRequestSource_Enum? source_) =>
      _$this._source_ = source_;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _payload;
  String? get payload => _$this._payload;
  set payload(String? payload) => _$this._payload = payload;

  ListBuilder<PortableRef>? _refs;
  ListBuilder<PortableRef> get refs =>
      _$this._refs ??= ListBuilder<PortableRef>();
  set refs(ListBuilder<PortableRef>? refs) => _$this._refs = refs;

  PlaylistImportRequestBuilder() {
    PlaylistImportRequest._defaults(this);
  }

  PlaylistImportRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _source_ = $v.source_;
      _name = $v.name;
      _payload = $v.payload;
      _refs = $v.refs?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaylistImportRequest other) {
    _$v = other as _$PlaylistImportRequest;
  }

  @override
  void update(void Function(PlaylistImportRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaylistImportRequest build() => _build();

  _$PlaylistImportRequest _build() {
    _$PlaylistImportRequest _$result;
    try {
      _$result =
          _$v ??
          _$PlaylistImportRequest._(
            source_: BuiltValueNullFieldError.checkNotNull(
              source_,
              r'PlaylistImportRequest',
              'source_',
            ),
            name: name,
            payload: payload,
            refs: _refs?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'refs';
        _refs?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlaylistImportRequest',
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
