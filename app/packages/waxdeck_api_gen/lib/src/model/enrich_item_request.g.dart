// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrich_item_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const EnrichItemRequestWantEnum _$enrichItemRequestWantEnum_cover =
    const EnrichItemRequestWantEnum._('cover');
const EnrichItemRequestWantEnum _$enrichItemRequestWantEnum_lyrics =
    const EnrichItemRequestWantEnum._('lyrics');
const EnrichItemRequestWantEnum _$enrichItemRequestWantEnum_genres =
    const EnrichItemRequestWantEnum._('genres');
const EnrichItemRequestWantEnum _$enrichItemRequestWantEnum_book =
    const EnrichItemRequestWantEnum._('book');
const EnrichItemRequestWantEnum
_$enrichItemRequestWantEnum_unknownDefaultOpenApi =
    const EnrichItemRequestWantEnum._('unknownDefaultOpenApi');

EnrichItemRequestWantEnum _$enrichItemRequestWantEnumValueOf(String name) {
  switch (name) {
    case 'cover':
      return _$enrichItemRequestWantEnum_cover;
    case 'lyrics':
      return _$enrichItemRequestWantEnum_lyrics;
    case 'genres':
      return _$enrichItemRequestWantEnum_genres;
    case 'book':
      return _$enrichItemRequestWantEnum_book;
    case 'unknownDefaultOpenApi':
      return _$enrichItemRequestWantEnum_unknownDefaultOpenApi;
    default:
      return _$enrichItemRequestWantEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<EnrichItemRequestWantEnum> _$enrichItemRequestWantEnumValues =
    BuiltSet<EnrichItemRequestWantEnum>(const <EnrichItemRequestWantEnum>[
      _$enrichItemRequestWantEnum_cover,
      _$enrichItemRequestWantEnum_lyrics,
      _$enrichItemRequestWantEnum_genres,
      _$enrichItemRequestWantEnum_book,
      _$enrichItemRequestWantEnum_unknownDefaultOpenApi,
    ]);

Serializer<EnrichItemRequestWantEnum> _$enrichItemRequestWantEnumSerializer =
    _$EnrichItemRequestWantEnumSerializer();

class _$EnrichItemRequestWantEnumSerializer
    implements PrimitiveSerializer<EnrichItemRequestWantEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'cover': 'cover',
    'lyrics': 'lyrics',
    'genres': 'genres',
    'book': 'book',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'cover': 'cover',
    'lyrics': 'lyrics',
    'genres': 'genres',
    'book': 'book',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[EnrichItemRequestWantEnum];
  @override
  final String wireName = 'EnrichItemRequestWantEnum';

  @override
  Object serialize(
    Serializers serializers,
    EnrichItemRequestWantEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  EnrichItemRequestWantEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => EnrichItemRequestWantEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$EnrichItemRequest extends EnrichItemRequest {
  @override
  final BuiltList<EnrichItemRequestWantEnum> want;

  factory _$EnrichItemRequest([
    void Function(EnrichItemRequestBuilder)? updates,
  ]) => (EnrichItemRequestBuilder()..update(updates))._build();

  _$EnrichItemRequest._({required this.want}) : super._();
  @override
  EnrichItemRequest rebuild(void Function(EnrichItemRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EnrichItemRequestBuilder toBuilder() =>
      EnrichItemRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichItemRequest && want == other.want;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, want.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'EnrichItemRequest',
    )..add('want', want)).toString();
  }
}

class EnrichItemRequestBuilder
    implements Builder<EnrichItemRequest, EnrichItemRequestBuilder> {
  _$EnrichItemRequest? _$v;

  ListBuilder<EnrichItemRequestWantEnum>? _want;
  ListBuilder<EnrichItemRequestWantEnum> get want =>
      _$this._want ??= ListBuilder<EnrichItemRequestWantEnum>();
  set want(ListBuilder<EnrichItemRequestWantEnum>? want) => _$this._want = want;

  EnrichItemRequestBuilder() {
    EnrichItemRequest._defaults(this);
  }

  EnrichItemRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _want = $v.want.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichItemRequest other) {
    _$v = other as _$EnrichItemRequest;
  }

  @override
  void update(void Function(EnrichItemRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichItemRequest build() => _build();

  _$EnrichItemRequest _build() {
    _$EnrichItemRequest _$result;
    try {
      _$result = _$v ?? _$EnrichItemRequest._(want: want.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'want';
        want.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EnrichItemRequest',
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
