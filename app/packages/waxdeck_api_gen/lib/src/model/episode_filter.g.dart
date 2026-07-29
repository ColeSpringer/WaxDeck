// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'episode_filter.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EpisodeFilter extends EpisodeFilter {
  @override
  final BuiltList<String>? include;
  @override
  final BuiltList<String>? exclude;

  factory _$EpisodeFilter([void Function(EpisodeFilterBuilder)? updates]) =>
      (EpisodeFilterBuilder()..update(updates))._build();

  _$EpisodeFilter._({this.include, this.exclude}) : super._();
  @override
  EpisodeFilter rebuild(void Function(EpisodeFilterBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EpisodeFilterBuilder toBuilder() => EpisodeFilterBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EpisodeFilter &&
        include == other.include &&
        exclude == other.exclude;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, include.hashCode);
    _$hash = $jc(_$hash, exclude.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EpisodeFilter')
          ..add('include', include)
          ..add('exclude', exclude))
        .toString();
  }
}

class EpisodeFilterBuilder
    implements Builder<EpisodeFilter, EpisodeFilterBuilder> {
  _$EpisodeFilter? _$v;

  ListBuilder<String>? _include;
  ListBuilder<String> get include => _$this._include ??= ListBuilder<String>();
  set include(ListBuilder<String>? include) => _$this._include = include;

  ListBuilder<String>? _exclude;
  ListBuilder<String> get exclude => _$this._exclude ??= ListBuilder<String>();
  set exclude(ListBuilder<String>? exclude) => _$this._exclude = exclude;

  EpisodeFilterBuilder() {
    EpisodeFilter._defaults(this);
  }

  EpisodeFilterBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _include = $v.include?.toBuilder();
      _exclude = $v.exclude?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EpisodeFilter other) {
    _$v = other as _$EpisodeFilter;
  }

  @override
  void update(void Function(EpisodeFilterBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EpisodeFilter build() => _build();

  _$EpisodeFilter _build() {
    _$EpisodeFilter _$result;
    try {
      _$result =
          _$v ??
          _$EpisodeFilter._(
            include: _include?.build(),
            exclude: _exclude?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'include';
        _include?.build();
        _$failedField = 'exclude';
        _exclude?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EpisodeFilter',
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
