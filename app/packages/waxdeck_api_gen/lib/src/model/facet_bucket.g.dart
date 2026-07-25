// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'facet_bucket.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FacetBucket extends FacetBucket {
  @override
  final String key;
  @override
  final String label;
  @override
  final int count;
  @override
  final String? entityPid;
  @override
  final bool? unknown;

  factory _$FacetBucket([void Function(FacetBucketBuilder)? updates]) =>
      (FacetBucketBuilder()..update(updates))._build();

  _$FacetBucket._({
    required this.key,
    required this.label,
    required this.count,
    this.entityPid,
    this.unknown,
  }) : super._();
  @override
  FacetBucket rebuild(void Function(FacetBucketBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FacetBucketBuilder toBuilder() => FacetBucketBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FacetBucket &&
        key == other.key &&
        label == other.label &&
        count == other.count &&
        entityPid == other.entityPid &&
        unknown == other.unknown;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, key.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, count.hashCode);
    _$hash = $jc(_$hash, entityPid.hashCode);
    _$hash = $jc(_$hash, unknown.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FacetBucket')
          ..add('key', key)
          ..add('label', label)
          ..add('count', count)
          ..add('entityPid', entityPid)
          ..add('unknown', unknown))
        .toString();
  }
}

class FacetBucketBuilder implements Builder<FacetBucket, FacetBucketBuilder> {
  _$FacetBucket? _$v;

  String? _key;
  String? get key => _$this._key;
  set key(String? key) => _$this._key = key;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  int? _count;
  int? get count => _$this._count;
  set count(int? count) => _$this._count = count;

  String? _entityPid;
  String? get entityPid => _$this._entityPid;
  set entityPid(String? entityPid) => _$this._entityPid = entityPid;

  bool? _unknown;
  bool? get unknown => _$this._unknown;
  set unknown(bool? unknown) => _$this._unknown = unknown;

  FacetBucketBuilder() {
    FacetBucket._defaults(this);
  }

  FacetBucketBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _key = $v.key;
      _label = $v.label;
      _count = $v.count;
      _entityPid = $v.entityPid;
      _unknown = $v.unknown;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FacetBucket other) {
    _$v = other as _$FacetBucket;
  }

  @override
  void update(void Function(FacetBucketBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FacetBucket build() => _build();

  _$FacetBucket _build() {
    final _$result =
        _$v ??
        _$FacetBucket._(
          key: BuiltValueNullFieldError.checkNotNull(
            key,
            r'FacetBucket',
            'key',
          ),
          label: BuiltValueNullFieldError.checkNotNull(
            label,
            r'FacetBucket',
            'label',
          ),
          count: BuiltValueNullFieldError.checkNotNull(
            count,
            r'FacetBucket',
            'count',
          ),
          entityPid: entityPid,
          unknown: unknown,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
