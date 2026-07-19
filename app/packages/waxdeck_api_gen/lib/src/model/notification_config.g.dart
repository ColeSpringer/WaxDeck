// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_config.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$NotificationConfig extends NotificationConfig {
  @override
  final String appriseUrl;
  @override
  final String? targets;
  @override
  final BuiltList<String> enabledEvents;
  @override
  final BuiltList<String> knownEvents;

  factory _$NotificationConfig([
    void Function(NotificationConfigBuilder)? updates,
  ]) => (NotificationConfigBuilder()..update(updates))._build();

  _$NotificationConfig._({
    required this.appriseUrl,
    this.targets,
    required this.enabledEvents,
    required this.knownEvents,
  }) : super._();
  @override
  NotificationConfig rebuild(
    void Function(NotificationConfigBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  NotificationConfigBuilder toBuilder() =>
      NotificationConfigBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NotificationConfig &&
        appriseUrl == other.appriseUrl &&
        targets == other.targets &&
        enabledEvents == other.enabledEvents &&
        knownEvents == other.knownEvents;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, appriseUrl.hashCode);
    _$hash = $jc(_$hash, targets.hashCode);
    _$hash = $jc(_$hash, enabledEvents.hashCode);
    _$hash = $jc(_$hash, knownEvents.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NotificationConfig')
          ..add('appriseUrl', appriseUrl)
          ..add('targets', targets)
          ..add('enabledEvents', enabledEvents)
          ..add('knownEvents', knownEvents))
        .toString();
  }
}

class NotificationConfigBuilder
    implements Builder<NotificationConfig, NotificationConfigBuilder> {
  _$NotificationConfig? _$v;

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

  ListBuilder<String>? _knownEvents;
  ListBuilder<String> get knownEvents =>
      _$this._knownEvents ??= ListBuilder<String>();
  set knownEvents(ListBuilder<String>? knownEvents) =>
      _$this._knownEvents = knownEvents;

  NotificationConfigBuilder() {
    NotificationConfig._defaults(this);
  }

  NotificationConfigBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _appriseUrl = $v.appriseUrl;
      _targets = $v.targets;
      _enabledEvents = $v.enabledEvents.toBuilder();
      _knownEvents = $v.knownEvents.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NotificationConfig other) {
    _$v = other as _$NotificationConfig;
  }

  @override
  void update(void Function(NotificationConfigBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NotificationConfig build() => _build();

  _$NotificationConfig _build() {
    _$NotificationConfig _$result;
    try {
      _$result =
          _$v ??
          _$NotificationConfig._(
            appriseUrl: BuiltValueNullFieldError.checkNotNull(
              appriseUrl,
              r'NotificationConfig',
              'appriseUrl',
            ),
            targets: targets,
            enabledEvents: enabledEvents.build(),
            knownEvents: knownEvents.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'enabledEvents';
        enabledEvents.build();
        _$failedField = 'knownEvents';
        knownEvents.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'NotificationConfig',
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
