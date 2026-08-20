// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'art_source.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ArtSource extends ArtSource {
  @override
  final String source_;
  @override
  final String? provider;
  @override
  final String? sourceUrl;
  @override
  final String? level;
  @override
  final bool? derived;
  @override
  final DateTime? updatedAt;

  factory _$ArtSource([void Function(ArtSourceBuilder)? updates]) =>
      (ArtSourceBuilder()..update(updates))._build();

  _$ArtSource._({
    required this.source_,
    this.provider,
    this.sourceUrl,
    this.level,
    this.derived,
    this.updatedAt,
  }) : super._();
  @override
  ArtSource rebuild(void Function(ArtSourceBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ArtSourceBuilder toBuilder() => ArtSourceBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ArtSource &&
        source_ == other.source_ &&
        provider == other.provider &&
        sourceUrl == other.sourceUrl &&
        level == other.level &&
        derived == other.derived &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, sourceUrl.hashCode);
    _$hash = $jc(_$hash, level.hashCode);
    _$hash = $jc(_$hash, derived.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ArtSource')
          ..add('source_', source_)
          ..add('provider', provider)
          ..add('sourceUrl', sourceUrl)
          ..add('level', level)
          ..add('derived', derived)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class ArtSourceBuilder implements Builder<ArtSource, ArtSourceBuilder> {
  _$ArtSource? _$v;

  String? _source_;
  String? get source_ => _$this._source_;
  set source_(String? source_) => _$this._source_ = source_;

  String? _provider;
  String? get provider => _$this._provider;
  set provider(String? provider) => _$this._provider = provider;

  String? _sourceUrl;
  String? get sourceUrl => _$this._sourceUrl;
  set sourceUrl(String? sourceUrl) => _$this._sourceUrl = sourceUrl;

  String? _level;
  String? get level => _$this._level;
  set level(String? level) => _$this._level = level;

  bool? _derived;
  bool? get derived => _$this._derived;
  set derived(bool? derived) => _$this._derived = derived;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  ArtSourceBuilder() {
    ArtSource._defaults(this);
  }

  ArtSourceBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _source_ = $v.source_;
      _provider = $v.provider;
      _sourceUrl = $v.sourceUrl;
      _level = $v.level;
      _derived = $v.derived;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ArtSource other) {
    _$v = other as _$ArtSource;
  }

  @override
  void update(void Function(ArtSourceBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ArtSource build() => _build();

  _$ArtSource _build() {
    final _$result =
        _$v ??
        _$ArtSource._(
          source_: BuiltValueNullFieldError.checkNotNull(
            source_,
            r'ArtSource',
            'source_',
          ),
          provider: provider,
          sourceUrl: sourceUrl,
          level: level,
          derived: derived,
          updatedAt: updatedAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
