// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upgrade_resolve_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpgradeResolveRequest extends UpgradeResolveRequest {
  @override
  final String keepItemPid;
  @override
  final BuiltList<String> removeItemPids;

  factory _$UpgradeResolveRequest([
    void Function(UpgradeResolveRequestBuilder)? updates,
  ]) => (UpgradeResolveRequestBuilder()..update(updates))._build();

  _$UpgradeResolveRequest._({
    required this.keepItemPid,
    required this.removeItemPids,
  }) : super._();
  @override
  UpgradeResolveRequest rebuild(
    void Function(UpgradeResolveRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  UpgradeResolveRequestBuilder toBuilder() =>
      UpgradeResolveRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpgradeResolveRequest &&
        keepItemPid == other.keepItemPid &&
        removeItemPids == other.removeItemPids;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, keepItemPid.hashCode);
    _$hash = $jc(_$hash, removeItemPids.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpgradeResolveRequest')
          ..add('keepItemPid', keepItemPid)
          ..add('removeItemPids', removeItemPids))
        .toString();
  }
}

class UpgradeResolveRequestBuilder
    implements Builder<UpgradeResolveRequest, UpgradeResolveRequestBuilder> {
  _$UpgradeResolveRequest? _$v;

  String? _keepItemPid;
  String? get keepItemPid => _$this._keepItemPid;
  set keepItemPid(String? keepItemPid) => _$this._keepItemPid = keepItemPid;

  ListBuilder<String>? _removeItemPids;
  ListBuilder<String> get removeItemPids =>
      _$this._removeItemPids ??= ListBuilder<String>();
  set removeItemPids(ListBuilder<String>? removeItemPids) =>
      _$this._removeItemPids = removeItemPids;

  UpgradeResolveRequestBuilder() {
    UpgradeResolveRequest._defaults(this);
  }

  UpgradeResolveRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _keepItemPid = $v.keepItemPid;
      _removeItemPids = $v.removeItemPids.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpgradeResolveRequest other) {
    _$v = other as _$UpgradeResolveRequest;
  }

  @override
  void update(void Function(UpgradeResolveRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpgradeResolveRequest build() => _build();

  _$UpgradeResolveRequest _build() {
    _$UpgradeResolveRequest _$result;
    try {
      _$result =
          _$v ??
          _$UpgradeResolveRequest._(
            keepItemPid: BuiltValueNullFieldError.checkNotNull(
              keepItemPid,
              r'UpgradeResolveRequest',
              'keepItemPid',
            ),
            removeItemPids: removeItemPids.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'removeItemPids';
        removeItemPids.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'UpgradeResolveRequest',
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
