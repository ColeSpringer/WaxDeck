// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrich_preview.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichPreview extends EnrichPreview {
  @override
  final BuiltList<EnrichFieldProposal> fields;
  @override
  final EnrichCoverProposal? cover;
  @override
  final BuiltList<String> skipped;

  factory _$EnrichPreview([void Function(EnrichPreviewBuilder)? updates]) =>
      (EnrichPreviewBuilder()..update(updates))._build();

  _$EnrichPreview._({required this.fields, this.cover, required this.skipped})
    : super._();
  @override
  EnrichPreview rebuild(void Function(EnrichPreviewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EnrichPreviewBuilder toBuilder() => EnrichPreviewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichPreview &&
        fields == other.fields &&
        cover == other.cover &&
        skipped == other.skipped;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, fields.hashCode);
    _$hash = $jc(_$hash, cover.hashCode);
    _$hash = $jc(_$hash, skipped.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EnrichPreview')
          ..add('fields', fields)
          ..add('cover', cover)
          ..add('skipped', skipped))
        .toString();
  }
}

class EnrichPreviewBuilder
    implements Builder<EnrichPreview, EnrichPreviewBuilder> {
  _$EnrichPreview? _$v;

  ListBuilder<EnrichFieldProposal>? _fields;
  ListBuilder<EnrichFieldProposal> get fields =>
      _$this._fields ??= ListBuilder<EnrichFieldProposal>();
  set fields(ListBuilder<EnrichFieldProposal>? fields) =>
      _$this._fields = fields;

  EnrichCoverProposalBuilder? _cover;
  EnrichCoverProposalBuilder get cover =>
      _$this._cover ??= EnrichCoverProposalBuilder();
  set cover(EnrichCoverProposalBuilder? cover) => _$this._cover = cover;

  ListBuilder<String>? _skipped;
  ListBuilder<String> get skipped => _$this._skipped ??= ListBuilder<String>();
  set skipped(ListBuilder<String>? skipped) => _$this._skipped = skipped;

  EnrichPreviewBuilder() {
    EnrichPreview._defaults(this);
  }

  EnrichPreviewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _fields = $v.fields.toBuilder();
      _cover = $v.cover?.toBuilder();
      _skipped = $v.skipped.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichPreview other) {
    _$v = other as _$EnrichPreview;
  }

  @override
  void update(void Function(EnrichPreviewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichPreview build() => _build();

  _$EnrichPreview _build() {
    _$EnrichPreview _$result;
    try {
      _$result =
          _$v ??
          _$EnrichPreview._(
            fields: fields.build(),
            cover: _cover?.build(),
            skipped: skipped.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'fields';
        fields.build();
        _$failedField = 'cover';
        _cover?.build();
        _$failedField = 'skipped';
        skipped.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EnrichPreview',
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
