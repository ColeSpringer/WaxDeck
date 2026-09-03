// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'item_acquisition_edit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ItemAcquisitionEdit extends ItemAcquisitionEdit {
  @override
  final String sourceType;
  @override
  final String? sourceUrl;
  @override
  final String? sourceId;
  @override
  final String? provider;
  @override
  final DateTime? acquiredAt;
  @override
  final bool? writeBack;
  @override
  final bool? lock;
  @override
  final bool? force;

  factory _$ItemAcquisitionEdit([
    void Function(ItemAcquisitionEditBuilder)? updates,
  ]) => (ItemAcquisitionEditBuilder()..update(updates))._build();

  _$ItemAcquisitionEdit._({
    required this.sourceType,
    this.sourceUrl,
    this.sourceId,
    this.provider,
    this.acquiredAt,
    this.writeBack,
    this.lock,
    this.force,
  }) : super._();
  @override
  ItemAcquisitionEdit rebuild(
    void Function(ItemAcquisitionEditBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  ItemAcquisitionEditBuilder toBuilder() =>
      ItemAcquisitionEditBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ItemAcquisitionEdit &&
        sourceType == other.sourceType &&
        sourceUrl == other.sourceUrl &&
        sourceId == other.sourceId &&
        provider == other.provider &&
        acquiredAt == other.acquiredAt &&
        writeBack == other.writeBack &&
        lock == other.lock &&
        force == other.force;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, sourceType.hashCode);
    _$hash = $jc(_$hash, sourceUrl.hashCode);
    _$hash = $jc(_$hash, sourceId.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, acquiredAt.hashCode);
    _$hash = $jc(_$hash, writeBack.hashCode);
    _$hash = $jc(_$hash, lock.hashCode);
    _$hash = $jc(_$hash, force.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ItemAcquisitionEdit')
          ..add('sourceType', sourceType)
          ..add('sourceUrl', sourceUrl)
          ..add('sourceId', sourceId)
          ..add('provider', provider)
          ..add('acquiredAt', acquiredAt)
          ..add('writeBack', writeBack)
          ..add('lock', lock)
          ..add('force', force))
        .toString();
  }
}

class ItemAcquisitionEditBuilder
    implements Builder<ItemAcquisitionEdit, ItemAcquisitionEditBuilder> {
  _$ItemAcquisitionEdit? _$v;

  String? _sourceType;
  String? get sourceType => _$this._sourceType;
  set sourceType(String? sourceType) => _$this._sourceType = sourceType;

  String? _sourceUrl;
  String? get sourceUrl => _$this._sourceUrl;
  set sourceUrl(String? sourceUrl) => _$this._sourceUrl = sourceUrl;

  String? _sourceId;
  String? get sourceId => _$this._sourceId;
  set sourceId(String? sourceId) => _$this._sourceId = sourceId;

  String? _provider;
  String? get provider => _$this._provider;
  set provider(String? provider) => _$this._provider = provider;

  DateTime? _acquiredAt;
  DateTime? get acquiredAt => _$this._acquiredAt;
  set acquiredAt(DateTime? acquiredAt) => _$this._acquiredAt = acquiredAt;

  bool? _writeBack;
  bool? get writeBack => _$this._writeBack;
  set writeBack(bool? writeBack) => _$this._writeBack = writeBack;

  bool? _lock;
  bool? get lock => _$this._lock;
  set lock(bool? lock) => _$this._lock = lock;

  bool? _force;
  bool? get force => _$this._force;
  set force(bool? force) => _$this._force = force;

  ItemAcquisitionEditBuilder() {
    ItemAcquisitionEdit._defaults(this);
  }

  ItemAcquisitionEditBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sourceType = $v.sourceType;
      _sourceUrl = $v.sourceUrl;
      _sourceId = $v.sourceId;
      _provider = $v.provider;
      _acquiredAt = $v.acquiredAt;
      _writeBack = $v.writeBack;
      _lock = $v.lock;
      _force = $v.force;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ItemAcquisitionEdit other) {
    _$v = other as _$ItemAcquisitionEdit;
  }

  @override
  void update(void Function(ItemAcquisitionEditBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ItemAcquisitionEdit build() => _build();

  _$ItemAcquisitionEdit _build() {
    final _$result =
        _$v ??
        _$ItemAcquisitionEdit._(
          sourceType: BuiltValueNullFieldError.checkNotNull(
            sourceType,
            r'ItemAcquisitionEdit',
            'sourceType',
          ),
          sourceUrl: sourceUrl,
          sourceId: sourceId,
          provider: provider,
          acquiredAt: acquiredAt,
          writeBack: writeBack,
          lock: lock,
          force: force,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
