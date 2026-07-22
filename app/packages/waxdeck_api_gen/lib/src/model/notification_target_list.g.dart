// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_target_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$NotificationTargetList extends NotificationTargetList {
  @override
  final BuiltList<NotificationTarget> targets;

  factory _$NotificationTargetList([
    void Function(NotificationTargetListBuilder)? updates,
  ]) => (NotificationTargetListBuilder()..update(updates))._build();

  _$NotificationTargetList._({required this.targets}) : super._();
  @override
  NotificationTargetList rebuild(
    void Function(NotificationTargetListBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  NotificationTargetListBuilder toBuilder() =>
      NotificationTargetListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NotificationTargetList && targets == other.targets;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, targets.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'NotificationTargetList',
    )..add('targets', targets)).toString();
  }
}

class NotificationTargetListBuilder
    implements Builder<NotificationTargetList, NotificationTargetListBuilder> {
  _$NotificationTargetList? _$v;

  ListBuilder<NotificationTarget>? _targets;
  ListBuilder<NotificationTarget> get targets =>
      _$this._targets ??= ListBuilder<NotificationTarget>();
  set targets(ListBuilder<NotificationTarget>? targets) =>
      _$this._targets = targets;

  NotificationTargetListBuilder() {
    NotificationTargetList._defaults(this);
  }

  NotificationTargetListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _targets = $v.targets.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NotificationTargetList other) {
    _$v = other as _$NotificationTargetList;
  }

  @override
  void update(void Function(NotificationTargetListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NotificationTargetList build() => _build();

  _$NotificationTargetList _build() {
    _$NotificationTargetList _$result;
    try {
      _$result = _$v ?? _$NotificationTargetList._(targets: targets.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'targets';
        targets.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'NotificationTargetList',
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
