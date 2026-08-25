// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrich_cover_proposal.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichCoverProposal extends EnrichCoverProposal {
  @override
  final String provider;
  @override
  final String data;
  @override
  final String? format;
  @override
  final String? sourceUrl;

  factory _$EnrichCoverProposal([
    void Function(EnrichCoverProposalBuilder)? updates,
  ]) => (EnrichCoverProposalBuilder()..update(updates))._build();

  _$EnrichCoverProposal._({
    required this.provider,
    required this.data,
    this.format,
    this.sourceUrl,
  }) : super._();
  @override
  EnrichCoverProposal rebuild(
    void Function(EnrichCoverProposalBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  EnrichCoverProposalBuilder toBuilder() =>
      EnrichCoverProposalBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichCoverProposal &&
        provider == other.provider &&
        data == other.data &&
        format == other.format &&
        sourceUrl == other.sourceUrl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, data.hashCode);
    _$hash = $jc(_$hash, format.hashCode);
    _$hash = $jc(_$hash, sourceUrl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EnrichCoverProposal')
          ..add('provider', provider)
          ..add('data', data)
          ..add('format', format)
          ..add('sourceUrl', sourceUrl))
        .toString();
  }
}

class EnrichCoverProposalBuilder
    implements Builder<EnrichCoverProposal, EnrichCoverProposalBuilder> {
  _$EnrichCoverProposal? _$v;

  String? _provider;
  String? get provider => _$this._provider;
  set provider(String? provider) => _$this._provider = provider;

  String? _data;
  String? get data => _$this._data;
  set data(String? data) => _$this._data = data;

  String? _format;
  String? get format => _$this._format;
  set format(String? format) => _$this._format = format;

  String? _sourceUrl;
  String? get sourceUrl => _$this._sourceUrl;
  set sourceUrl(String? sourceUrl) => _$this._sourceUrl = sourceUrl;

  EnrichCoverProposalBuilder() {
    EnrichCoverProposal._defaults(this);
  }

  EnrichCoverProposalBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _provider = $v.provider;
      _data = $v.data;
      _format = $v.format;
      _sourceUrl = $v.sourceUrl;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichCoverProposal other) {
    _$v = other as _$EnrichCoverProposal;
  }

  @override
  void update(void Function(EnrichCoverProposalBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichCoverProposal build() => _build();

  _$EnrichCoverProposal _build() {
    final _$result =
        _$v ??
        _$EnrichCoverProposal._(
          provider: BuiltValueNullFieldError.checkNotNull(
            provider,
            r'EnrichCoverProposal',
            'provider',
          ),
          data: BuiltValueNullFieldError.checkNotNull(
            data,
            r'EnrichCoverProposal',
            'data',
          ),
          format: format,
          sourceUrl: sourceUrl,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
