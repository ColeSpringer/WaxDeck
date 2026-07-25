// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'genre_tree.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const GenreTreeSource_Enum _$genreTreeSourceEnum_default_ =
    const GenreTreeSource_Enum._('default_');
const GenreTreeSource_Enum _$genreTreeSourceEnum_custom =
    const GenreTreeSource_Enum._('custom');

GenreTreeSource_Enum _$genreTreeSourceEnumValueOf(String name) {
  switch (name) {
    case 'default_':
      return _$genreTreeSourceEnum_default_;
    case 'custom':
      return _$genreTreeSourceEnum_custom;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<GenreTreeSource_Enum> _$genreTreeSourceEnumValues =
    BuiltSet<GenreTreeSource_Enum>(const <GenreTreeSource_Enum>[
      _$genreTreeSourceEnum_default_,
      _$genreTreeSourceEnum_custom,
    ]);

Serializer<GenreTreeSource_Enum> _$genreTreeSourceEnumSerializer =
    _$GenreTreeSource_EnumSerializer();

class _$GenreTreeSource_EnumSerializer
    implements PrimitiveSerializer<GenreTreeSource_Enum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'default_': 'default',
    'custom': 'custom',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'default': 'default_',
    'custom': 'custom',
  };

  @override
  final Iterable<Type> types = const <Type>[GenreTreeSource_Enum];
  @override
  final String wireName = 'GenreTreeSource_Enum';

  @override
  Object serialize(
    Serializers serializers,
    GenreTreeSource_Enum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  GenreTreeSource_Enum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => GenreTreeSource_Enum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$GenreTree extends GenreTree {
  @override
  final GenreTreeSource_Enum source_;
  @override
  final BuiltList<GenreNode> genres;

  factory _$GenreTree([void Function(GenreTreeBuilder)? updates]) =>
      (GenreTreeBuilder()..update(updates))._build();

  _$GenreTree._({required this.source_, required this.genres}) : super._();
  @override
  GenreTree rebuild(void Function(GenreTreeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GenreTreeBuilder toBuilder() => GenreTreeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GenreTree &&
        source_ == other.source_ &&
        genres == other.genres;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, genres.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GenreTree')
          ..add('source_', source_)
          ..add('genres', genres))
        .toString();
  }
}

class GenreTreeBuilder implements Builder<GenreTree, GenreTreeBuilder> {
  _$GenreTree? _$v;

  GenreTreeSource_Enum? _source_;
  GenreTreeSource_Enum? get source_ => _$this._source_;
  set source_(GenreTreeSource_Enum? source_) => _$this._source_ = source_;

  ListBuilder<GenreNode>? _genres;
  ListBuilder<GenreNode> get genres =>
      _$this._genres ??= ListBuilder<GenreNode>();
  set genres(ListBuilder<GenreNode>? genres) => _$this._genres = genres;

  GenreTreeBuilder() {
    GenreTree._defaults(this);
  }

  GenreTreeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _source_ = $v.source_;
      _genres = $v.genres.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GenreTree other) {
    _$v = other as _$GenreTree;
  }

  @override
  void update(void Function(GenreTreeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GenreTree build() => _build();

  _$GenreTree _build() {
    _$GenreTree _$result;
    try {
      _$result =
          _$v ??
          _$GenreTree._(
            source_: BuiltValueNullFieldError.checkNotNull(
              source_,
              r'GenreTree',
              'source_',
            ),
            genres: genres.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'genres';
        genres.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'GenreTree',
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
