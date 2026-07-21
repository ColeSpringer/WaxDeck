// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'duplicate_entity.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DuplicateEntity extends DuplicateEntity {
  @override
  final String pid;
  @override
  final String name;
  @override
  final int? itemCount;

  factory _$DuplicateEntity([void Function(DuplicateEntityBuilder)? updates]) =>
      (DuplicateEntityBuilder()..update(updates))._build();

  _$DuplicateEntity._({required this.pid, required this.name, this.itemCount})
    : super._();
  @override
  DuplicateEntity rebuild(void Function(DuplicateEntityBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DuplicateEntityBuilder toBuilder() => DuplicateEntityBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DuplicateEntity &&
        pid == other.pid &&
        name == other.name &&
        itemCount == other.itemCount;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, itemCount.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DuplicateEntity')
          ..add('pid', pid)
          ..add('name', name)
          ..add('itemCount', itemCount))
        .toString();
  }
}

class DuplicateEntityBuilder
    implements Builder<DuplicateEntity, DuplicateEntityBuilder> {
  _$DuplicateEntity? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  int? _itemCount;
  int? get itemCount => _$this._itemCount;
  set itemCount(int? itemCount) => _$this._itemCount = itemCount;

  DuplicateEntityBuilder() {
    DuplicateEntity._defaults(this);
  }

  DuplicateEntityBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _name = $v.name;
      _itemCount = $v.itemCount;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DuplicateEntity other) {
    _$v = other as _$DuplicateEntity;
  }

  @override
  void update(void Function(DuplicateEntityBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DuplicateEntity build() => _build();

  _$DuplicateEntity _build() {
    final _$result =
        _$v ??
        _$DuplicateEntity._(
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'DuplicateEntity',
            'pid',
          ),
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'DuplicateEntity',
            'name',
          ),
          itemCount: itemCount,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
