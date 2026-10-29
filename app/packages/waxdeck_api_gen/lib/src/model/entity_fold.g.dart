// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entity_fold.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EntityFold extends EntityFold {
  @override
  final String entityType;
  @override
  final String key;
  @override
  final String spelling;
  @override
  final String? facet;
  @override
  final String? folder;
  @override
  final String? library_;
  @override
  final String entityPid;
  @override
  final String entityName;
  @override
  final DateTime createdAt;

  factory _$EntityFold([void Function(EntityFoldBuilder)? updates]) =>
      (EntityFoldBuilder()..update(updates))._build();

  _$EntityFold._({
    required this.entityType,
    required this.key,
    required this.spelling,
    this.facet,
    this.folder,
    this.library_,
    required this.entityPid,
    required this.entityName,
    required this.createdAt,
  }) : super._();
  @override
  EntityFold rebuild(void Function(EntityFoldBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EntityFoldBuilder toBuilder() => EntityFoldBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EntityFold &&
        entityType == other.entityType &&
        key == other.key &&
        spelling == other.spelling &&
        facet == other.facet &&
        folder == other.folder &&
        library_ == other.library_ &&
        entityPid == other.entityPid &&
        entityName == other.entityName &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entityType.hashCode);
    _$hash = $jc(_$hash, key.hashCode);
    _$hash = $jc(_$hash, spelling.hashCode);
    _$hash = $jc(_$hash, facet.hashCode);
    _$hash = $jc(_$hash, folder.hashCode);
    _$hash = $jc(_$hash, library_.hashCode);
    _$hash = $jc(_$hash, entityPid.hashCode);
    _$hash = $jc(_$hash, entityName.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EntityFold')
          ..add('entityType', entityType)
          ..add('key', key)
          ..add('spelling', spelling)
          ..add('facet', facet)
          ..add('folder', folder)
          ..add('library_', library_)
          ..add('entityPid', entityPid)
          ..add('entityName', entityName)
          ..add('createdAt', createdAt))
        .toString();
  }
}

class EntityFoldBuilder implements Builder<EntityFold, EntityFoldBuilder> {
  _$EntityFold? _$v;

  String? _entityType;
  String? get entityType => _$this._entityType;
  set entityType(String? entityType) => _$this._entityType = entityType;

  String? _key;
  String? get key => _$this._key;
  set key(String? key) => _$this._key = key;

  String? _spelling;
  String? get spelling => _$this._spelling;
  set spelling(String? spelling) => _$this._spelling = spelling;

  String? _facet;
  String? get facet => _$this._facet;
  set facet(String? facet) => _$this._facet = facet;

  String? _folder;
  String? get folder => _$this._folder;
  set folder(String? folder) => _$this._folder = folder;

  String? _library_;
  String? get library_ => _$this._library_;
  set library_(String? library_) => _$this._library_ = library_;

  String? _entityPid;
  String? get entityPid => _$this._entityPid;
  set entityPid(String? entityPid) => _$this._entityPid = entityPid;

  String? _entityName;
  String? get entityName => _$this._entityName;
  set entityName(String? entityName) => _$this._entityName = entityName;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  EntityFoldBuilder() {
    EntityFold._defaults(this);
  }

  EntityFoldBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entityType = $v.entityType;
      _key = $v.key;
      _spelling = $v.spelling;
      _facet = $v.facet;
      _folder = $v.folder;
      _library_ = $v.library_;
      _entityPid = $v.entityPid;
      _entityName = $v.entityName;
      _createdAt = $v.createdAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EntityFold other) {
    _$v = other as _$EntityFold;
  }

  @override
  void update(void Function(EntityFoldBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EntityFold build() => _build();

  _$EntityFold _build() {
    final _$result =
        _$v ??
        _$EntityFold._(
          entityType: BuiltValueNullFieldError.checkNotNull(
            entityType,
            r'EntityFold',
            'entityType',
          ),
          key: BuiltValueNullFieldError.checkNotNull(key, r'EntityFold', 'key'),
          spelling: BuiltValueNullFieldError.checkNotNull(
            spelling,
            r'EntityFold',
            'spelling',
          ),
          facet: facet,
          folder: folder,
          library_: library_,
          entityPid: BuiltValueNullFieldError.checkNotNull(
            entityPid,
            r'EntityFold',
            'entityPid',
          ),
          entityName: BuiltValueNullFieldError.checkNotNull(
            entityName,
            r'EntityFold',
            'entityName',
          ),
          createdAt: BuiltValueNullFieldError.checkNotNull(
            createdAt,
            r'EntityFold',
            'createdAt',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
