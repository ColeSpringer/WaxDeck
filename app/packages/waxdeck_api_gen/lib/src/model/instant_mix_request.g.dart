// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'instant_mix_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$InstantMixRequest extends InstantMixRequest {
  @override
  final String? seedPid;
  @override
  final String? genre;
  @override
  final num? adventurousness;
  @override
  final int? size;
  @override
  final BuiltList<String>? excludePids;

  factory _$InstantMixRequest([
    void Function(InstantMixRequestBuilder)? updates,
  ]) => (InstantMixRequestBuilder()..update(updates))._build();

  _$InstantMixRequest._({
    this.seedPid,
    this.genre,
    this.adventurousness,
    this.size,
    this.excludePids,
  }) : super._();
  @override
  InstantMixRequest rebuild(void Function(InstantMixRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InstantMixRequestBuilder toBuilder() =>
      InstantMixRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InstantMixRequest &&
        seedPid == other.seedPid &&
        genre == other.genre &&
        adventurousness == other.adventurousness &&
        size == other.size &&
        excludePids == other.excludePids;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, seedPid.hashCode);
    _$hash = $jc(_$hash, genre.hashCode);
    _$hash = $jc(_$hash, adventurousness.hashCode);
    _$hash = $jc(_$hash, size.hashCode);
    _$hash = $jc(_$hash, excludePids.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'InstantMixRequest')
          ..add('seedPid', seedPid)
          ..add('genre', genre)
          ..add('adventurousness', adventurousness)
          ..add('size', size)
          ..add('excludePids', excludePids))
        .toString();
  }
}

class InstantMixRequestBuilder
    implements Builder<InstantMixRequest, InstantMixRequestBuilder> {
  _$InstantMixRequest? _$v;

  String? _seedPid;
  String? get seedPid => _$this._seedPid;
  set seedPid(String? seedPid) => _$this._seedPid = seedPid;

  String? _genre;
  String? get genre => _$this._genre;
  set genre(String? genre) => _$this._genre = genre;

  num? _adventurousness;
  num? get adventurousness => _$this._adventurousness;
  set adventurousness(num? adventurousness) =>
      _$this._adventurousness = adventurousness;

  int? _size;
  int? get size => _$this._size;
  set size(int? size) => _$this._size = size;

  ListBuilder<String>? _excludePids;
  ListBuilder<String> get excludePids =>
      _$this._excludePids ??= ListBuilder<String>();
  set excludePids(ListBuilder<String>? excludePids) =>
      _$this._excludePids = excludePids;

  InstantMixRequestBuilder() {
    InstantMixRequest._defaults(this);
  }

  InstantMixRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _seedPid = $v.seedPid;
      _genre = $v.genre;
      _adventurousness = $v.adventurousness;
      _size = $v.size;
      _excludePids = $v.excludePids?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(InstantMixRequest other) {
    _$v = other as _$InstantMixRequest;
  }

  @override
  void update(void Function(InstantMixRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InstantMixRequest build() => _build();

  _$InstantMixRequest _build() {
    _$InstantMixRequest _$result;
    try {
      _$result =
          _$v ??
          _$InstantMixRequest._(
            seedPid: seedPid,
            genre: genre,
            adventurousness: adventurousness,
            size: size,
            excludePids: _excludePids?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'excludePids';
        _excludePids?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'InstantMixRequest',
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
