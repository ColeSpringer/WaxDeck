// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'genre_node.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GenreNode extends GenreNode {
  @override
  final String name;
  @override
  final String? parent;
  @override
  final BuiltList<String>? aliases;

  factory _$GenreNode([void Function(GenreNodeBuilder)? updates]) =>
      (GenreNodeBuilder()..update(updates))._build();

  _$GenreNode._({required this.name, this.parent, this.aliases}) : super._();
  @override
  GenreNode rebuild(void Function(GenreNodeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GenreNodeBuilder toBuilder() => GenreNodeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GenreNode &&
        name == other.name &&
        parent == other.parent &&
        aliases == other.aliases;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, parent.hashCode);
    _$hash = $jc(_$hash, aliases.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GenreNode')
          ..add('name', name)
          ..add('parent', parent)
          ..add('aliases', aliases))
        .toString();
  }
}

class GenreNodeBuilder implements Builder<GenreNode, GenreNodeBuilder> {
  _$GenreNode? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _parent;
  String? get parent => _$this._parent;
  set parent(String? parent) => _$this._parent = parent;

  ListBuilder<String>? _aliases;
  ListBuilder<String> get aliases => _$this._aliases ??= ListBuilder<String>();
  set aliases(ListBuilder<String>? aliases) => _$this._aliases = aliases;

  GenreNodeBuilder() {
    GenreNode._defaults(this);
  }

  GenreNodeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _parent = $v.parent;
      _aliases = $v.aliases?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GenreNode other) {
    _$v = other as _$GenreNode;
  }

  @override
  void update(void Function(GenreNodeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GenreNode build() => _build();

  _$GenreNode _build() {
    _$GenreNode _$result;
    try {
      _$result =
          _$v ??
          _$GenreNode._(
            name: BuiltValueNullFieldError.checkNotNull(
              name,
              r'GenreNode',
              'name',
            ),
            parent: parent,
            aliases: _aliases?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'aliases';
        _aliases?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'GenreNode',
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
