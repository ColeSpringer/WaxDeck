// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'item_acquisition.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ItemAcquisition extends ItemAcquisition {
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
  final bool? locked;

  factory _$ItemAcquisition([void Function(ItemAcquisitionBuilder)? updates]) =>
      (ItemAcquisitionBuilder()..update(updates))._build();

  _$ItemAcquisition._({
    required this.sourceType,
    this.sourceUrl,
    this.sourceId,
    this.provider,
    this.acquiredAt,
    this.locked,
  }) : super._();
  @override
  ItemAcquisition rebuild(void Function(ItemAcquisitionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ItemAcquisitionBuilder toBuilder() => ItemAcquisitionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ItemAcquisition &&
        sourceType == other.sourceType &&
        sourceUrl == other.sourceUrl &&
        sourceId == other.sourceId &&
        provider == other.provider &&
        acquiredAt == other.acquiredAt &&
        locked == other.locked;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, sourceType.hashCode);
    _$hash = $jc(_$hash, sourceUrl.hashCode);
    _$hash = $jc(_$hash, sourceId.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, acquiredAt.hashCode);
    _$hash = $jc(_$hash, locked.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ItemAcquisition')
          ..add('sourceType', sourceType)
          ..add('sourceUrl', sourceUrl)
          ..add('sourceId', sourceId)
          ..add('provider', provider)
          ..add('acquiredAt', acquiredAt)
          ..add('locked', locked))
        .toString();
  }
}

class ItemAcquisitionBuilder
    implements Builder<ItemAcquisition, ItemAcquisitionBuilder> {
  _$ItemAcquisition? _$v;

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

  bool? _locked;
  bool? get locked => _$this._locked;
  set locked(bool? locked) => _$this._locked = locked;

  ItemAcquisitionBuilder() {
    ItemAcquisition._defaults(this);
  }

  ItemAcquisitionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sourceType = $v.sourceType;
      _sourceUrl = $v.sourceUrl;
      _sourceId = $v.sourceId;
      _provider = $v.provider;
      _acquiredAt = $v.acquiredAt;
      _locked = $v.locked;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ItemAcquisition other) {
    _$v = other as _$ItemAcquisition;
  }

  @override
  void update(void Function(ItemAcquisitionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ItemAcquisition build() => _build();

  _$ItemAcquisition _build() {
    final _$result =
        _$v ??
        _$ItemAcquisition._(
          sourceType: BuiltValueNullFieldError.checkNotNull(
            sourceType,
            r'ItemAcquisition',
            'sourceType',
          ),
          sourceUrl: sourceUrl,
          sourceId: sourceId,
          provider: provider,
          acquiredAt: acquiredAt,
          locked: locked,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
