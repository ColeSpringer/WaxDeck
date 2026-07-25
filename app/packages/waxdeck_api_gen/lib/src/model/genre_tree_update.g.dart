// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'genre_tree_update.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GenreTreeUpdate extends GenreTreeUpdate {
  @override
  final BuiltList<GenreNode> genres;

  factory _$GenreTreeUpdate([void Function(GenreTreeUpdateBuilder)? updates]) =>
      (GenreTreeUpdateBuilder()..update(updates))._build();

  _$GenreTreeUpdate._({required this.genres}) : super._();
  @override
  GenreTreeUpdate rebuild(void Function(GenreTreeUpdateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GenreTreeUpdateBuilder toBuilder() => GenreTreeUpdateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GenreTreeUpdate && genres == other.genres;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, genres.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'GenreTreeUpdate',
    )..add('genres', genres)).toString();
  }
}

class GenreTreeUpdateBuilder
    implements Builder<GenreTreeUpdate, GenreTreeUpdateBuilder> {
  _$GenreTreeUpdate? _$v;

  ListBuilder<GenreNode>? _genres;
  ListBuilder<GenreNode> get genres =>
      _$this._genres ??= ListBuilder<GenreNode>();
  set genres(ListBuilder<GenreNode>? genres) => _$this._genres = genres;

  GenreTreeUpdateBuilder() {
    GenreTreeUpdate._defaults(this);
  }

  GenreTreeUpdateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _genres = $v.genres.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GenreTreeUpdate other) {
    _$v = other as _$GenreTreeUpdate;
  }

  @override
  void update(void Function(GenreTreeUpdateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GenreTreeUpdate build() => _build();

  _$GenreTreeUpdate _build() {
    _$GenreTreeUpdate _$result;
    try {
      _$result = _$v ?? _$GenreTreeUpdate._(genres: genres.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'genres';
        genres.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'GenreTreeUpdate',
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
