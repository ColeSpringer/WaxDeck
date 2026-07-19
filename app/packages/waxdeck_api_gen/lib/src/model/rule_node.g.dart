// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rule_node.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RuleNode extends RuleNode {
  @override
  final String type;
  @override
  final BuiltList<RuleNode>? nodes;
  @override
  final RuleNode? node;
  @override
  final String? field;
  @override
  final String? op;
  @override
  final String? value;
  @override
  final BuiltList<String>? values;

  factory _$RuleNode([void Function(RuleNodeBuilder)? updates]) =>
      (RuleNodeBuilder()..update(updates))._build();

  _$RuleNode._({
    required this.type,
    this.nodes,
    this.node,
    this.field,
    this.op,
    this.value,
    this.values,
  }) : super._();
  @override
  RuleNode rebuild(void Function(RuleNodeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RuleNodeBuilder toBuilder() => RuleNodeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RuleNode &&
        type == other.type &&
        nodes == other.nodes &&
        node == other.node &&
        field == other.field &&
        op == other.op &&
        value == other.value &&
        values == other.values;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, nodes.hashCode);
    _$hash = $jc(_$hash, node.hashCode);
    _$hash = $jc(_$hash, field.hashCode);
    _$hash = $jc(_$hash, op.hashCode);
    _$hash = $jc(_$hash, value.hashCode);
    _$hash = $jc(_$hash, values.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RuleNode')
          ..add('type', type)
          ..add('nodes', nodes)
          ..add('node', node)
          ..add('field', field)
          ..add('op', op)
          ..add('value', value)
          ..add('values', values))
        .toString();
  }
}

class RuleNodeBuilder implements Builder<RuleNode, RuleNodeBuilder> {
  _$RuleNode? _$v;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  ListBuilder<RuleNode>? _nodes;
  ListBuilder<RuleNode> get nodes => _$this._nodes ??= ListBuilder<RuleNode>();
  set nodes(ListBuilder<RuleNode>? nodes) => _$this._nodes = nodes;

  RuleNodeBuilder? _node;
  RuleNodeBuilder get node => _$this._node ??= RuleNodeBuilder();
  set node(RuleNodeBuilder? node) => _$this._node = node;

  String? _field;
  String? get field => _$this._field;
  set field(String? field) => _$this._field = field;

  String? _op;
  String? get op => _$this._op;
  set op(String? op) => _$this._op = op;

  String? _value;
  String? get value => _$this._value;
  set value(String? value) => _$this._value = value;

  ListBuilder<String>? _values;
  ListBuilder<String> get values => _$this._values ??= ListBuilder<String>();
  set values(ListBuilder<String>? values) => _$this._values = values;

  RuleNodeBuilder() {
    RuleNode._defaults(this);
  }

  RuleNodeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _nodes = $v.nodes?.toBuilder();
      _node = $v.node?.toBuilder();
      _field = $v.field;
      _op = $v.op;
      _value = $v.value;
      _values = $v.values?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RuleNode other) {
    _$v = other as _$RuleNode;
  }

  @override
  void update(void Function(RuleNodeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RuleNode build() => _build();

  _$RuleNode _build() {
    _$RuleNode _$result;
    try {
      _$result =
          _$v ??
          _$RuleNode._(
            type: BuiltValueNullFieldError.checkNotNull(
              type,
              r'RuleNode',
              'type',
            ),
            nodes: _nodes?.build(),
            node: _node?.build(),
            field: field,
            op: op,
            value: value,
            values: _values?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'nodes';
        _nodes?.build();
        _$failedField = 'node';
        _node?.build();

        _$failedField = 'values';
        _values?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'RuleNode',
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
