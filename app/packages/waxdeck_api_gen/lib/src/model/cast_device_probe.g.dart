// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cast_device_probe.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CastDeviceProbe extends CastDeviceProbe {
  @override
  final String endpointId;
  @override
  final String name;
  @override
  final String kind;
  @override
  final BuiltList<CastPreflightBase> bases;

  factory _$CastDeviceProbe([void Function(CastDeviceProbeBuilder)? updates]) =>
      (CastDeviceProbeBuilder()..update(updates))._build();

  _$CastDeviceProbe._({
    required this.endpointId,
    required this.name,
    required this.kind,
    required this.bases,
  }) : super._();
  @override
  CastDeviceProbe rebuild(void Function(CastDeviceProbeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CastDeviceProbeBuilder toBuilder() => CastDeviceProbeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CastDeviceProbe &&
        endpointId == other.endpointId &&
        name == other.name &&
        kind == other.kind &&
        bases == other.bases;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, endpointId.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, bases.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CastDeviceProbe')
          ..add('endpointId', endpointId)
          ..add('name', name)
          ..add('kind', kind)
          ..add('bases', bases))
        .toString();
  }
}

class CastDeviceProbeBuilder
    implements Builder<CastDeviceProbe, CastDeviceProbeBuilder> {
  _$CastDeviceProbe? _$v;

  String? _endpointId;
  String? get endpointId => _$this._endpointId;
  set endpointId(String? endpointId) => _$this._endpointId = endpointId;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _kind;
  String? get kind => _$this._kind;
  set kind(String? kind) => _$this._kind = kind;

  ListBuilder<CastPreflightBase>? _bases;
  ListBuilder<CastPreflightBase> get bases =>
      _$this._bases ??= ListBuilder<CastPreflightBase>();
  set bases(ListBuilder<CastPreflightBase>? bases) => _$this._bases = bases;

  CastDeviceProbeBuilder() {
    CastDeviceProbe._defaults(this);
  }

  CastDeviceProbeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _endpointId = $v.endpointId;
      _name = $v.name;
      _kind = $v.kind;
      _bases = $v.bases.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CastDeviceProbe other) {
    _$v = other as _$CastDeviceProbe;
  }

  @override
  void update(void Function(CastDeviceProbeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CastDeviceProbe build() => _build();

  _$CastDeviceProbe _build() {
    _$CastDeviceProbe _$result;
    try {
      _$result =
          _$v ??
          _$CastDeviceProbe._(
            endpointId: BuiltValueNullFieldError.checkNotNull(
              endpointId,
              r'CastDeviceProbe',
              'endpointId',
            ),
            name: BuiltValueNullFieldError.checkNotNull(
              name,
              r'CastDeviceProbe',
              'name',
            ),
            kind: BuiltValueNullFieldError.checkNotNull(
              kind,
              r'CastDeviceProbe',
              'kind',
            ),
            bases: bases.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'bases';
        bases.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'CastDeviceProbe',
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
