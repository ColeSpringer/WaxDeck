// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'organize_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OrganizeRequest extends OrganizeRequest {
  @override
  final String profile;
  @override
  final BuiltList<String>? itemPids;

  factory _$OrganizeRequest([void Function(OrganizeRequestBuilder)? updates]) =>
      (OrganizeRequestBuilder()..update(updates))._build();

  _$OrganizeRequest._({required this.profile, this.itemPids}) : super._();
  @override
  OrganizeRequest rebuild(void Function(OrganizeRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OrganizeRequestBuilder toBuilder() => OrganizeRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OrganizeRequest &&
        profile == other.profile &&
        itemPids == other.itemPids;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, profile.hashCode);
    _$hash = $jc(_$hash, itemPids.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OrganizeRequest')
          ..add('profile', profile)
          ..add('itemPids', itemPids))
        .toString();
  }
}

class OrganizeRequestBuilder
    implements Builder<OrganizeRequest, OrganizeRequestBuilder> {
  _$OrganizeRequest? _$v;

  String? _profile;
  String? get profile => _$this._profile;
  set profile(String? profile) => _$this._profile = profile;

  ListBuilder<String>? _itemPids;
  ListBuilder<String> get itemPids =>
      _$this._itemPids ??= ListBuilder<String>();
  set itemPids(ListBuilder<String>? itemPids) => _$this._itemPids = itemPids;

  OrganizeRequestBuilder() {
    OrganizeRequest._defaults(this);
  }

  OrganizeRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _profile = $v.profile;
      _itemPids = $v.itemPids?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OrganizeRequest other) {
    _$v = other as _$OrganizeRequest;
  }

  @override
  void update(void Function(OrganizeRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OrganizeRequest build() => _build();

  _$OrganizeRequest _build() {
    _$OrganizeRequest _$result;
    try {
      _$result =
          _$v ??
          _$OrganizeRequest._(
            profile: BuiltValueNullFieldError.checkNotNull(
              profile,
              r'OrganizeRequest',
              'profile',
            ),
            itemPids: _itemPids?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'itemPids';
        _itemPids?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'OrganizeRequest',
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
