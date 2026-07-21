// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'candidate_component.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CandidateComponent extends CandidateComponent {
  @override
  final String name;
  @override
  final double distance;
  @override
  final double weight;

  factory _$CandidateComponent([
    void Function(CandidateComponentBuilder)? updates,
  ]) => (CandidateComponentBuilder()..update(updates))._build();

  _$CandidateComponent._({
    required this.name,
    required this.distance,
    required this.weight,
  }) : super._();
  @override
  CandidateComponent rebuild(
    void Function(CandidateComponentBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  CandidateComponentBuilder toBuilder() =>
      CandidateComponentBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CandidateComponent &&
        name == other.name &&
        distance == other.distance &&
        weight == other.weight;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, distance.hashCode);
    _$hash = $jc(_$hash, weight.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CandidateComponent')
          ..add('name', name)
          ..add('distance', distance)
          ..add('weight', weight))
        .toString();
  }
}

class CandidateComponentBuilder
    implements Builder<CandidateComponent, CandidateComponentBuilder> {
  _$CandidateComponent? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  double? _distance;
  double? get distance => _$this._distance;
  set distance(double? distance) => _$this._distance = distance;

  double? _weight;
  double? get weight => _$this._weight;
  set weight(double? weight) => _$this._weight = weight;

  CandidateComponentBuilder() {
    CandidateComponent._defaults(this);
  }

  CandidateComponentBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _distance = $v.distance;
      _weight = $v.weight;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CandidateComponent other) {
    _$v = other as _$CandidateComponent;
  }

  @override
  void update(void Function(CandidateComponentBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CandidateComponent build() => _build();

  _$CandidateComponent _build() {
    final _$result =
        _$v ??
        _$CandidateComponent._(
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'CandidateComponent',
            'name',
          ),
          distance: BuiltValueNullFieldError.checkNotNull(
            distance,
            r'CandidateComponent',
            'distance',
          ),
          weight: BuiltValueNullFieldError.checkNotNull(
            weight,
            r'CandidateComponent',
            'weight',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
