// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'skip_map.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SkipMap extends SkipMap {
  @override
  final String state;
  @override
  final String? essenceHash;
  @override
  final int? partIndex;
  @override
  final String? version;
  @override
  final double? thresholdDb;
  @override
  final double? minSeconds;
  @override
  final BuiltList<SkipSpan>? spans;
  @override
  final DateTime? updatedAt;

  factory _$SkipMap([void Function(SkipMapBuilder)? updates]) =>
      (SkipMapBuilder()..update(updates))._build();

  _$SkipMap._({
    required this.state,
    this.essenceHash,
    this.partIndex,
    this.version,
    this.thresholdDb,
    this.minSeconds,
    this.spans,
    this.updatedAt,
  }) : super._();
  @override
  SkipMap rebuild(void Function(SkipMapBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SkipMapBuilder toBuilder() => SkipMapBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SkipMap &&
        state == other.state &&
        essenceHash == other.essenceHash &&
        partIndex == other.partIndex &&
        version == other.version &&
        thresholdDb == other.thresholdDb &&
        minSeconds == other.minSeconds &&
        spans == other.spans &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, state.hashCode);
    _$hash = $jc(_$hash, essenceHash.hashCode);
    _$hash = $jc(_$hash, partIndex.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jc(_$hash, thresholdDb.hashCode);
    _$hash = $jc(_$hash, minSeconds.hashCode);
    _$hash = $jc(_$hash, spans.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SkipMap')
          ..add('state', state)
          ..add('essenceHash', essenceHash)
          ..add('partIndex', partIndex)
          ..add('version', version)
          ..add('thresholdDb', thresholdDb)
          ..add('minSeconds', minSeconds)
          ..add('spans', spans)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class SkipMapBuilder implements Builder<SkipMap, SkipMapBuilder> {
  _$SkipMap? _$v;

  String? _state;
  String? get state => _$this._state;
  set state(String? state) => _$this._state = state;

  String? _essenceHash;
  String? get essenceHash => _$this._essenceHash;
  set essenceHash(String? essenceHash) => _$this._essenceHash = essenceHash;

  int? _partIndex;
  int? get partIndex => _$this._partIndex;
  set partIndex(int? partIndex) => _$this._partIndex = partIndex;

  String? _version;
  String? get version => _$this._version;
  set version(String? version) => _$this._version = version;

  double? _thresholdDb;
  double? get thresholdDb => _$this._thresholdDb;
  set thresholdDb(double? thresholdDb) => _$this._thresholdDb = thresholdDb;

  double? _minSeconds;
  double? get minSeconds => _$this._minSeconds;
  set minSeconds(double? minSeconds) => _$this._minSeconds = minSeconds;

  ListBuilder<SkipSpan>? _spans;
  ListBuilder<SkipSpan> get spans => _$this._spans ??= ListBuilder<SkipSpan>();
  set spans(ListBuilder<SkipSpan>? spans) => _$this._spans = spans;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  SkipMapBuilder() {
    SkipMap._defaults(this);
  }

  SkipMapBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _state = $v.state;
      _essenceHash = $v.essenceHash;
      _partIndex = $v.partIndex;
      _version = $v.version;
      _thresholdDb = $v.thresholdDb;
      _minSeconds = $v.minSeconds;
      _spans = $v.spans?.toBuilder();
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SkipMap other) {
    _$v = other as _$SkipMap;
  }

  @override
  void update(void Function(SkipMapBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SkipMap build() => _build();

  _$SkipMap _build() {
    _$SkipMap _$result;
    try {
      _$result =
          _$v ??
          _$SkipMap._(
            state: BuiltValueNullFieldError.checkNotNull(
              state,
              r'SkipMap',
              'state',
            ),
            essenceHash: essenceHash,
            partIndex: partIndex,
            version: version,
            thresholdDb: thresholdDb,
            minSeconds: minSeconds,
            spans: _spans?.build(),
            updatedAt: updatedAt,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'spans';
        _spans?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'SkipMap',
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
