// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nsp_report.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const NspReportDirectionEnum _$nspReportDirectionEnum_export_ =
    const NspReportDirectionEnum._('export_');
const NspReportDirectionEnum _$nspReportDirectionEnum_import_ =
    const NspReportDirectionEnum._('import_');
const NspReportDirectionEnum _$nspReportDirectionEnum_unknownDefaultOpenApi =
    const NspReportDirectionEnum._('unknownDefaultOpenApi');

NspReportDirectionEnum _$nspReportDirectionEnumValueOf(String name) {
  switch (name) {
    case 'export_':
      return _$nspReportDirectionEnum_export_;
    case 'import_':
      return _$nspReportDirectionEnum_import_;
    case 'unknownDefaultOpenApi':
      return _$nspReportDirectionEnum_unknownDefaultOpenApi;
    default:
      return _$nspReportDirectionEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<NspReportDirectionEnum> _$nspReportDirectionEnumValues =
    BuiltSet<NspReportDirectionEnum>(const <NspReportDirectionEnum>[
      _$nspReportDirectionEnum_export_,
      _$nspReportDirectionEnum_import_,
      _$nspReportDirectionEnum_unknownDefaultOpenApi,
    ]);

Serializer<NspReportDirectionEnum> _$nspReportDirectionEnumSerializer =
    _$NspReportDirectionEnumSerializer();

class _$NspReportDirectionEnumSerializer
    implements PrimitiveSerializer<NspReportDirectionEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'export_': 'export',
    'import_': 'import',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'export': 'export_',
    'import': 'import_',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[NspReportDirectionEnum];
  @override
  final String wireName = 'NspReportDirectionEnum';

  @override
  Object serialize(
    Serializers serializers,
    NspReportDirectionEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  NspReportDirectionEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => NspReportDirectionEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$NspReport extends NspReport {
  @override
  final NspReportDirectionEnum direction;
  @override
  final BuiltList<NspGap>? gaps;
  @override
  final BuiltList<NspGap>? notes;
  @override
  final bool? truncated;
  @override
  final String? ruleHash;
  @override
  final SmartRule? rule;

  factory _$NspReport([void Function(NspReportBuilder)? updates]) =>
      (NspReportBuilder()..update(updates))._build();

  _$NspReport._({
    required this.direction,
    this.gaps,
    this.notes,
    this.truncated,
    this.ruleHash,
    this.rule,
  }) : super._();
  @override
  NspReport rebuild(void Function(NspReportBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  NspReportBuilder toBuilder() => NspReportBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NspReport &&
        direction == other.direction &&
        gaps == other.gaps &&
        notes == other.notes &&
        truncated == other.truncated &&
        ruleHash == other.ruleHash &&
        rule == other.rule;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, direction.hashCode);
    _$hash = $jc(_$hash, gaps.hashCode);
    _$hash = $jc(_$hash, notes.hashCode);
    _$hash = $jc(_$hash, truncated.hashCode);
    _$hash = $jc(_$hash, ruleHash.hashCode);
    _$hash = $jc(_$hash, rule.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NspReport')
          ..add('direction', direction)
          ..add('gaps', gaps)
          ..add('notes', notes)
          ..add('truncated', truncated)
          ..add('ruleHash', ruleHash)
          ..add('rule', rule))
        .toString();
  }
}

class NspReportBuilder implements Builder<NspReport, NspReportBuilder> {
  _$NspReport? _$v;

  NspReportDirectionEnum? _direction;
  NspReportDirectionEnum? get direction => _$this._direction;
  set direction(NspReportDirectionEnum? direction) =>
      _$this._direction = direction;

  ListBuilder<NspGap>? _gaps;
  ListBuilder<NspGap> get gaps => _$this._gaps ??= ListBuilder<NspGap>();
  set gaps(ListBuilder<NspGap>? gaps) => _$this._gaps = gaps;

  ListBuilder<NspGap>? _notes;
  ListBuilder<NspGap> get notes => _$this._notes ??= ListBuilder<NspGap>();
  set notes(ListBuilder<NspGap>? notes) => _$this._notes = notes;

  bool? _truncated;
  bool? get truncated => _$this._truncated;
  set truncated(bool? truncated) => _$this._truncated = truncated;

  String? _ruleHash;
  String? get ruleHash => _$this._ruleHash;
  set ruleHash(String? ruleHash) => _$this._ruleHash = ruleHash;

  SmartRuleBuilder? _rule;
  SmartRuleBuilder get rule => _$this._rule ??= SmartRuleBuilder();
  set rule(SmartRuleBuilder? rule) => _$this._rule = rule;

  NspReportBuilder() {
    NspReport._defaults(this);
  }

  NspReportBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _direction = $v.direction;
      _gaps = $v.gaps?.toBuilder();
      _notes = $v.notes?.toBuilder();
      _truncated = $v.truncated;
      _ruleHash = $v.ruleHash;
      _rule = $v.rule?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NspReport other) {
    _$v = other as _$NspReport;
  }

  @override
  void update(void Function(NspReportBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NspReport build() => _build();

  _$NspReport _build() {
    _$NspReport _$result;
    try {
      _$result =
          _$v ??
          _$NspReport._(
            direction: BuiltValueNullFieldError.checkNotNull(
              direction,
              r'NspReport',
              'direction',
            ),
            gaps: _gaps?.build(),
            notes: _notes?.build(),
            truncated: truncated,
            ruleHash: ruleHash,
            rule: _rule?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'gaps';
        _gaps?.build();
        _$failedField = 'notes';
        _notes?.build();

        _$failedField = 'rule';
        _rule?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'NspReport',
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
