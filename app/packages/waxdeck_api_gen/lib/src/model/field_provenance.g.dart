// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'field_provenance.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FieldProvenance extends FieldProvenance {
  @override
  final String field;
  @override
  final String source_;
  @override
  final String? provider;
  @override
  final String? sourceUrl;
  @override
  final bool locked;
  @override
  final DateTime? updatedAt;

  factory _$FieldProvenance([void Function(FieldProvenanceBuilder)? updates]) =>
      (FieldProvenanceBuilder()..update(updates))._build();

  _$FieldProvenance._({
    required this.field,
    required this.source_,
    this.provider,
    this.sourceUrl,
    required this.locked,
    this.updatedAt,
  }) : super._();
  @override
  FieldProvenance rebuild(void Function(FieldProvenanceBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FieldProvenanceBuilder toBuilder() => FieldProvenanceBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FieldProvenance &&
        field == other.field &&
        source_ == other.source_ &&
        provider == other.provider &&
        sourceUrl == other.sourceUrl &&
        locked == other.locked &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, field.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, sourceUrl.hashCode);
    _$hash = $jc(_$hash, locked.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FieldProvenance')
          ..add('field', field)
          ..add('source_', source_)
          ..add('provider', provider)
          ..add('sourceUrl', sourceUrl)
          ..add('locked', locked)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class FieldProvenanceBuilder
    implements Builder<FieldProvenance, FieldProvenanceBuilder> {
  _$FieldProvenance? _$v;

  String? _field;
  String? get field => _$this._field;
  set field(String? field) => _$this._field = field;

  String? _source_;
  String? get source_ => _$this._source_;
  set source_(String? source_) => _$this._source_ = source_;

  String? _provider;
  String? get provider => _$this._provider;
  set provider(String? provider) => _$this._provider = provider;

  String? _sourceUrl;
  String? get sourceUrl => _$this._sourceUrl;
  set sourceUrl(String? sourceUrl) => _$this._sourceUrl = sourceUrl;

  bool? _locked;
  bool? get locked => _$this._locked;
  set locked(bool? locked) => _$this._locked = locked;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  FieldProvenanceBuilder() {
    FieldProvenance._defaults(this);
  }

  FieldProvenanceBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _field = $v.field;
      _source_ = $v.source_;
      _provider = $v.provider;
      _sourceUrl = $v.sourceUrl;
      _locked = $v.locked;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FieldProvenance other) {
    _$v = other as _$FieldProvenance;
  }

  @override
  void update(void Function(FieldProvenanceBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FieldProvenance build() => _build();

  _$FieldProvenance _build() {
    final _$result =
        _$v ??
        _$FieldProvenance._(
          field: BuiltValueNullFieldError.checkNotNull(
            field,
            r'FieldProvenance',
            'field',
          ),
          source_: BuiltValueNullFieldError.checkNotNull(
            source_,
            r'FieldProvenance',
            'source_',
          ),
          provider: provider,
          sourceUrl: sourceUrl,
          locked: BuiltValueNullFieldError.checkNotNull(
            locked,
            r'FieldProvenance',
            'locked',
          ),
          updatedAt: updatedAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
