// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'starred_entities.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$StarredEntities extends StarredEntities {
  @override
  final BuiltList<SearchHit> artists;
  @override
  final BuiltList<SearchHit> albums;

  factory _$StarredEntities([void Function(StarredEntitiesBuilder)? updates]) =>
      (StarredEntitiesBuilder()..update(updates))._build();

  _$StarredEntities._({required this.artists, required this.albums})
    : super._();
  @override
  StarredEntities rebuild(void Function(StarredEntitiesBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  StarredEntitiesBuilder toBuilder() => StarredEntitiesBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is StarredEntities &&
        artists == other.artists &&
        albums == other.albums;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, artists.hashCode);
    _$hash = $jc(_$hash, albums.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'StarredEntities')
          ..add('artists', artists)
          ..add('albums', albums))
        .toString();
  }
}

class StarredEntitiesBuilder
    implements Builder<StarredEntities, StarredEntitiesBuilder> {
  _$StarredEntities? _$v;

  ListBuilder<SearchHit>? _artists;
  ListBuilder<SearchHit> get artists =>
      _$this._artists ??= ListBuilder<SearchHit>();
  set artists(ListBuilder<SearchHit>? artists) => _$this._artists = artists;

  ListBuilder<SearchHit>? _albums;
  ListBuilder<SearchHit> get albums =>
      _$this._albums ??= ListBuilder<SearchHit>();
  set albums(ListBuilder<SearchHit>? albums) => _$this._albums = albums;

  StarredEntitiesBuilder() {
    StarredEntities._defaults(this);
  }

  StarredEntitiesBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _artists = $v.artists.toBuilder();
      _albums = $v.albums.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(StarredEntities other) {
    _$v = other as _$StarredEntities;
  }

  @override
  void update(void Function(StarredEntitiesBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  StarredEntities build() => _build();

  _$StarredEntities _build() {
    _$StarredEntities _$result;
    try {
      _$result =
          _$v ??
          _$StarredEntities._(artists: artists.build(), albums: albums.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'artists';
        artists.build();
        _$failedField = 'albums';
        albums.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'StarredEntities',
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
