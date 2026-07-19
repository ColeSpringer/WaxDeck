// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_config_update.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$NotificationConfigUpdate extends NotificationConfigUpdate {
  @override
  final String appriseUrl;
  @override
  final String? targets;
  @override
  final BuiltList<String> enabledEvents;

  factory _$NotificationConfigUpdate([
    void Function(NotificationConfigUpdateBuilder)? updates,
  ]) => (NotificationConfigUpdateBuilder()..update(updates))._build();

  _$NotificationConfigUpdate._({
    required this.appriseUrl,
    this.targets,
    required this.enabledEvents,
  }) : super._();
  @override
  NotificationConfigUpdate rebuild(
    void Function(NotificationConfigUpdateBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  NotificationConfigUpdateBuilder toBuilder() =>
      NotificationConfigUpdateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NotificationConfigUpdate &&
        appriseUrl == other.appriseUrl &&
        targets == other.targets &&
        enabledEvents == other.enabledEvents;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, appriseUrl.hashCode);
    _$hash = $jc(_$hash, targets.hashCode);
    _$hash = $jc(_$hash, enabledEvents.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NotificationConfigUpdate')
          ..add('appriseUrl', appriseUrl)
          ..add('targets', targets)
          ..add('enabledEvents', enabledEvents))
        .toString();
  }
}

class NotificationConfigUpdateBuilder
    implements
        Builder<NotificationConfigUpdate, NotificationConfigUpdateBuilder> {
  _$NotificationConfigUpdate? _$v;

  String? _appriseUrl;
  String? get appriseUrl => _$this._appriseUrl;
  set appriseUrl(String? appriseUrl) => _$this._appriseUrl = appriseUrl;

  String? _targets;
  String? get targets => _$this._targets;
  set targets(String? targets) => _$this._targets = targets;

  ListBuilder<String>? _enabledEvents;
  ListBuilder<String> get enabledEvents =>
      _$this._enabledEvents ??= ListBuilder<String>();
  set enabledEvents(ListBuilder<String>? enabledEvents) =>
      _$this._enabledEvents = enabledEvents;

  NotificationConfigUpdateBuilder() {
    NotificationConfigUpdate._defaults(this);
  }

  NotificationConfigUpdateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _appriseUrl = $v.appriseUrl;
      _targets = $v.targets;
      _enabledEvents = $v.enabledEvents.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NotificationConfigUpdate other) {
    _$v = other as _$NotificationConfigUpdate;
  }

  @override
  void update(void Function(NotificationConfigUpdateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NotificationConfigUpdate build() => _build();

  _$NotificationConfigUpdate _build() {
    _$NotificationConfigUpdate _$result;
    try {
      _$result =
          _$v ??
          _$NotificationConfigUpdate._(
            appriseUrl: BuiltValueNullFieldError.checkNotNull(
              appriseUrl,
              r'NotificationConfigUpdate',
              'appriseUrl',
            ),
            targets: targets,
            enabledEvents: enabledEvents.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'enabledEvents';
        enabledEvents.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'NotificationConfigUpdate',
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
