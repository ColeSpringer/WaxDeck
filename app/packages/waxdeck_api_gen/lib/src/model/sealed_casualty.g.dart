// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sealed_casualty.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SealedCasualty extends SealedCasualty {
  @override
  final String kind;
  @override
  final String name;

  factory _$SealedCasualty([void Function(SealedCasualtyBuilder)? updates]) =>
      (SealedCasualtyBuilder()..update(updates))._build();

  _$SealedCasualty._({required this.kind, required this.name}) : super._();
  @override
  SealedCasualty rebuild(void Function(SealedCasualtyBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SealedCasualtyBuilder toBuilder() => SealedCasualtyBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SealedCasualty && kind == other.kind && name == other.name;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SealedCasualty')
          ..add('kind', kind)
          ..add('name', name))
        .toString();
  }
}

class SealedCasualtyBuilder
    implements Builder<SealedCasualty, SealedCasualtyBuilder> {
  _$SealedCasualty? _$v;

  String? _kind;
  String? get kind => _$this._kind;
  set kind(String? kind) => _$this._kind = kind;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  SealedCasualtyBuilder() {
    SealedCasualty._defaults(this);
  }

  SealedCasualtyBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _name = $v.name;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SealedCasualty other) {
    _$v = other as _$SealedCasualty;
  }

  @override
  void update(void Function(SealedCasualtyBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SealedCasualty build() => _build();

  _$SealedCasualty _build() {
    final _$result =
        _$v ??
        _$SealedCasualty._(
          kind: BuiltValueNullFieldError.checkNotNull(
            kind,
            r'SealedCasualty',
            'kind',
          ),
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'SealedCasualty',
            'name',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
