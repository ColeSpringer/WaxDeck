// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrich_proposal.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichProposal extends EnrichProposal {
  @override
  final BuiltList<EnrichFieldProposal>? fields;
  @override
  final EnrichCoverProposal? cover;

  factory _$EnrichProposal([void Function(EnrichProposalBuilder)? updates]) =>
      (EnrichProposalBuilder()..update(updates))._build();

  _$EnrichProposal._({this.fields, this.cover}) : super._();
  @override
  EnrichProposal rebuild(void Function(EnrichProposalBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EnrichProposalBuilder toBuilder() => EnrichProposalBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichProposal &&
        fields == other.fields &&
        cover == other.cover;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, fields.hashCode);
    _$hash = $jc(_$hash, cover.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EnrichProposal')
          ..add('fields', fields)
          ..add('cover', cover))
        .toString();
  }
}

class EnrichProposalBuilder
    implements Builder<EnrichProposal, EnrichProposalBuilder> {
  _$EnrichProposal? _$v;

  ListBuilder<EnrichFieldProposal>? _fields;
  ListBuilder<EnrichFieldProposal> get fields =>
      _$this._fields ??= ListBuilder<EnrichFieldProposal>();
  set fields(ListBuilder<EnrichFieldProposal>? fields) =>
      _$this._fields = fields;

  EnrichCoverProposalBuilder? _cover;
  EnrichCoverProposalBuilder get cover =>
      _$this._cover ??= EnrichCoverProposalBuilder();
  set cover(EnrichCoverProposalBuilder? cover) => _$this._cover = cover;

  EnrichProposalBuilder() {
    EnrichProposal._defaults(this);
  }

  EnrichProposalBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _fields = $v.fields?.toBuilder();
      _cover = $v.cover?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichProposal other) {
    _$v = other as _$EnrichProposal;
  }

  @override
  void update(void Function(EnrichProposalBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichProposal build() => _build();

  _$EnrichProposal _build() {
    _$EnrichProposal _$result;
    try {
      _$result =
          _$v ??
          _$EnrichProposal._(fields: _fields?.build(), cover: _cover?.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'fields';
        _fields?.build();
        _$failedField = 'cover';
        _cover?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EnrichProposal',
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
