// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audit_event.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AuditEvent extends AuditEvent {
  @override
  final String id;
  @override
  final String? actorId;
  @override
  final String? actorName;
  @override
  final String action;
  @override
  final String? targetKind;
  @override
  final String? targetPid;
  @override
  final String? targetName;
  @override
  final BuiltMap<String, JsonObject?>? detail;
  @override
  final DateTime createdAt;

  factory _$AuditEvent([void Function(AuditEventBuilder)? updates]) =>
      (AuditEventBuilder()..update(updates))._build();

  _$AuditEvent._({
    required this.id,
    this.actorId,
    this.actorName,
    required this.action,
    this.targetKind,
    this.targetPid,
    this.targetName,
    this.detail,
    required this.createdAt,
  }) : super._();
  @override
  AuditEvent rebuild(void Function(AuditEventBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AuditEventBuilder toBuilder() => AuditEventBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AuditEvent &&
        id == other.id &&
        actorId == other.actorId &&
        actorName == other.actorName &&
        action == other.action &&
        targetKind == other.targetKind &&
        targetPid == other.targetPid &&
        targetName == other.targetName &&
        detail == other.detail &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, actorId.hashCode);
    _$hash = $jc(_$hash, actorName.hashCode);
    _$hash = $jc(_$hash, action.hashCode);
    _$hash = $jc(_$hash, targetKind.hashCode);
    _$hash = $jc(_$hash, targetPid.hashCode);
    _$hash = $jc(_$hash, targetName.hashCode);
    _$hash = $jc(_$hash, detail.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AuditEvent')
          ..add('id', id)
          ..add('actorId', actorId)
          ..add('actorName', actorName)
          ..add('action', action)
          ..add('targetKind', targetKind)
          ..add('targetPid', targetPid)
          ..add('targetName', targetName)
          ..add('detail', detail)
          ..add('createdAt', createdAt))
        .toString();
  }
}

class AuditEventBuilder implements Builder<AuditEvent, AuditEventBuilder> {
  _$AuditEvent? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _actorId;
  String? get actorId => _$this._actorId;
  set actorId(String? actorId) => _$this._actorId = actorId;

  String? _actorName;
  String? get actorName => _$this._actorName;
  set actorName(String? actorName) => _$this._actorName = actorName;

  String? _action;
  String? get action => _$this._action;
  set action(String? action) => _$this._action = action;

  String? _targetKind;
  String? get targetKind => _$this._targetKind;
  set targetKind(String? targetKind) => _$this._targetKind = targetKind;

  String? _targetPid;
  String? get targetPid => _$this._targetPid;
  set targetPid(String? targetPid) => _$this._targetPid = targetPid;

  String? _targetName;
  String? get targetName => _$this._targetName;
  set targetName(String? targetName) => _$this._targetName = targetName;

  MapBuilder<String, JsonObject?>? _detail;
  MapBuilder<String, JsonObject?> get detail =>
      _$this._detail ??= MapBuilder<String, JsonObject?>();
  set detail(MapBuilder<String, JsonObject?>? detail) =>
      _$this._detail = detail;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  AuditEventBuilder() {
    AuditEvent._defaults(this);
  }

  AuditEventBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _actorId = $v.actorId;
      _actorName = $v.actorName;
      _action = $v.action;
      _targetKind = $v.targetKind;
      _targetPid = $v.targetPid;
      _targetName = $v.targetName;
      _detail = $v.detail?.toBuilder();
      _createdAt = $v.createdAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AuditEvent other) {
    _$v = other as _$AuditEvent;
  }

  @override
  void update(void Function(AuditEventBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AuditEvent build() => _build();

  _$AuditEvent _build() {
    _$AuditEvent _$result;
    try {
      _$result =
          _$v ??
          _$AuditEvent._(
            id: BuiltValueNullFieldError.checkNotNull(id, r'AuditEvent', 'id'),
            actorId: actorId,
            actorName: actorName,
            action: BuiltValueNullFieldError.checkNotNull(
              action,
              r'AuditEvent',
              'action',
            ),
            targetKind: targetKind,
            targetPid: targetPid,
            targetName: targetName,
            detail: _detail?.build(),
            createdAt: BuiltValueNullFieldError.checkNotNull(
              createdAt,
              r'AuditEvent',
              'createdAt',
            ),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'detail';
        _detail?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'AuditEvent',
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
