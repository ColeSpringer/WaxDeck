// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_fix_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$HealthFixRequest extends HealthFixRequest {
  @override
  final String rule;
  @override
  final BuiltList<String>? itemPids;

  factory _$HealthFixRequest([
    void Function(HealthFixRequestBuilder)? updates,
  ]) => (HealthFixRequestBuilder()..update(updates))._build();

  _$HealthFixRequest._({required this.rule, this.itemPids}) : super._();
  @override
  HealthFixRequest rebuild(void Function(HealthFixRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HealthFixRequestBuilder toBuilder() =>
      HealthFixRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HealthFixRequest &&
        rule == other.rule &&
        itemPids == other.itemPids;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, rule.hashCode);
    _$hash = $jc(_$hash, itemPids.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HealthFixRequest')
          ..add('rule', rule)
          ..add('itemPids', itemPids))
        .toString();
  }
}

class HealthFixRequestBuilder
    implements Builder<HealthFixRequest, HealthFixRequestBuilder> {
  _$HealthFixRequest? _$v;

  String? _rule;
  String? get rule => _$this._rule;
  set rule(String? rule) => _$this._rule = rule;

  ListBuilder<String>? _itemPids;
  ListBuilder<String> get itemPids =>
      _$this._itemPids ??= ListBuilder<String>();
  set itemPids(ListBuilder<String>? itemPids) => _$this._itemPids = itemPids;

  HealthFixRequestBuilder() {
    HealthFixRequest._defaults(this);
  }

  HealthFixRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _rule = $v.rule;
      _itemPids = $v.itemPids?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HealthFixRequest other) {
    _$v = other as _$HealthFixRequest;
  }

  @override
  void update(void Function(HealthFixRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HealthFixRequest build() => _build();

  _$HealthFixRequest _build() {
    _$HealthFixRequest _$result;
    try {
      _$result =
          _$v ??
          _$HealthFixRequest._(
            rule: BuiltValueNullFieldError.checkNotNull(
              rule,
              r'HealthFixRequest',
              'rule',
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
          r'HealthFixRequest',
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
