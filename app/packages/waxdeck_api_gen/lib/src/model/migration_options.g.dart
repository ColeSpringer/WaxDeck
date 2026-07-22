// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'migration_options.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MigrationOptions extends MigrationOptions {
  @override
  final bool? stars;
  @override
  final bool? ratings;
  @override
  final bool? history;
  @override
  final bool? progress;

  factory _$MigrationOptions([
    void Function(MigrationOptionsBuilder)? updates,
  ]) => (MigrationOptionsBuilder()..update(updates))._build();

  _$MigrationOptions._({this.stars, this.ratings, this.history, this.progress})
    : super._();
  @override
  MigrationOptions rebuild(void Function(MigrationOptionsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MigrationOptionsBuilder toBuilder() =>
      MigrationOptionsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MigrationOptions &&
        stars == other.stars &&
        ratings == other.ratings &&
        history == other.history &&
        progress == other.progress;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, stars.hashCode);
    _$hash = $jc(_$hash, ratings.hashCode);
    _$hash = $jc(_$hash, history.hashCode);
    _$hash = $jc(_$hash, progress.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MigrationOptions')
          ..add('stars', stars)
          ..add('ratings', ratings)
          ..add('history', history)
          ..add('progress', progress))
        .toString();
  }
}

class MigrationOptionsBuilder
    implements Builder<MigrationOptions, MigrationOptionsBuilder> {
  _$MigrationOptions? _$v;

  bool? _stars;
  bool? get stars => _$this._stars;
  set stars(bool? stars) => _$this._stars = stars;

  bool? _ratings;
  bool? get ratings => _$this._ratings;
  set ratings(bool? ratings) => _$this._ratings = ratings;

  bool? _history;
  bool? get history => _$this._history;
  set history(bool? history) => _$this._history = history;

  bool? _progress;
  bool? get progress => _$this._progress;
  set progress(bool? progress) => _$this._progress = progress;

  MigrationOptionsBuilder() {
    MigrationOptions._defaults(this);
  }

  MigrationOptionsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _stars = $v.stars;
      _ratings = $v.ratings;
      _history = $v.history;
      _progress = $v.progress;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MigrationOptions other) {
    _$v = other as _$MigrationOptions;
  }

  @override
  void update(void Function(MigrationOptionsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MigrationOptions build() => _build();

  _$MigrationOptions _build() {
    final _$result =
        _$v ??
        _$MigrationOptions._(
          stars: stars,
          ratings: ratings,
          history: history,
          progress: progress,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
