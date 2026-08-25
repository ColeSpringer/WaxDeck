// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrich_field_proposal.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichFieldProposal extends EnrichFieldProposal {
  @override
  final String name;
  @override
  final String? current;
  @override
  final String proposed;
  @override
  final String provider;

  factory _$EnrichFieldProposal([
    void Function(EnrichFieldProposalBuilder)? updates,
  ]) => (EnrichFieldProposalBuilder()..update(updates))._build();

  _$EnrichFieldProposal._({
    required this.name,
    this.current,
    required this.proposed,
    required this.provider,
  }) : super._();
  @override
  EnrichFieldProposal rebuild(
    void Function(EnrichFieldProposalBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  EnrichFieldProposalBuilder toBuilder() =>
      EnrichFieldProposalBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichFieldProposal &&
        name == other.name &&
        current == other.current &&
        proposed == other.proposed &&
        provider == other.provider;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, current.hashCode);
    _$hash = $jc(_$hash, proposed.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EnrichFieldProposal')
          ..add('name', name)
          ..add('current', current)
          ..add('proposed', proposed)
          ..add('provider', provider))
        .toString();
  }
}

class EnrichFieldProposalBuilder
    implements Builder<EnrichFieldProposal, EnrichFieldProposalBuilder> {
  _$EnrichFieldProposal? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _current;
  String? get current => _$this._current;
  set current(String? current) => _$this._current = current;

  String? _proposed;
  String? get proposed => _$this._proposed;
  set proposed(String? proposed) => _$this._proposed = proposed;

  String? _provider;
  String? get provider => _$this._provider;
  set provider(String? provider) => _$this._provider = provider;

  EnrichFieldProposalBuilder() {
    EnrichFieldProposal._defaults(this);
  }

  EnrichFieldProposalBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _current = $v.current;
      _proposed = $v.proposed;
      _provider = $v.provider;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichFieldProposal other) {
    _$v = other as _$EnrichFieldProposal;
  }

  @override
  void update(void Function(EnrichFieldProposalBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichFieldProposal build() => _build();

  _$EnrichFieldProposal _build() {
    final _$result =
        _$v ??
        _$EnrichFieldProposal._(
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'EnrichFieldProposal',
            'name',
          ),
          current: current,
          proposed: BuiltValueNullFieldError.checkNotNull(
            proposed,
            r'EnrichFieldProposal',
            'proposed',
          ),
          provider: BuiltValueNullFieldError.checkNotNull(
            provider,
            r'EnrichFieldProposal',
            'provider',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
