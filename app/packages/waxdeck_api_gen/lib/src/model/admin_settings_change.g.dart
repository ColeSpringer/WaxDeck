// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_settings_change.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AdminSettingsChange extends AdminSettingsChange {
  @override
  final bool? signupEnabled;
  @override
  final bool? readOnly;
  @override
  final bool? sonicAnalysis;
  @override
  final bool? enrichmentWriteTags;
  @override
  final bool? radioExternalArt;
  @override
  final int? backupKeepCount;
  @override
  final int? backupKeepBytes;
  @override
  final int? trashRetentionDays;
  @override
  final int? taskRetentionDays;

  factory _$AdminSettingsChange([
    void Function(AdminSettingsChangeBuilder)? updates,
  ]) => (AdminSettingsChangeBuilder()..update(updates))._build();

  _$AdminSettingsChange._({
    this.signupEnabled,
    this.readOnly,
    this.sonicAnalysis,
    this.enrichmentWriteTags,
    this.radioExternalArt,
    this.backupKeepCount,
    this.backupKeepBytes,
    this.trashRetentionDays,
    this.taskRetentionDays,
  }) : super._();
  @override
  AdminSettingsChange rebuild(
    void Function(AdminSettingsChangeBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  AdminSettingsChangeBuilder toBuilder() =>
      AdminSettingsChangeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AdminSettingsChange &&
        signupEnabled == other.signupEnabled &&
        readOnly == other.readOnly &&
        sonicAnalysis == other.sonicAnalysis &&
        enrichmentWriteTags == other.enrichmentWriteTags &&
        radioExternalArt == other.radioExternalArt &&
        backupKeepCount == other.backupKeepCount &&
        backupKeepBytes == other.backupKeepBytes &&
        trashRetentionDays == other.trashRetentionDays &&
        taskRetentionDays == other.taskRetentionDays;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, signupEnabled.hashCode);
    _$hash = $jc(_$hash, readOnly.hashCode);
    _$hash = $jc(_$hash, sonicAnalysis.hashCode);
    _$hash = $jc(_$hash, enrichmentWriteTags.hashCode);
    _$hash = $jc(_$hash, radioExternalArt.hashCode);
    _$hash = $jc(_$hash, backupKeepCount.hashCode);
    _$hash = $jc(_$hash, backupKeepBytes.hashCode);
    _$hash = $jc(_$hash, trashRetentionDays.hashCode);
    _$hash = $jc(_$hash, taskRetentionDays.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AdminSettingsChange')
          ..add('signupEnabled', signupEnabled)
          ..add('readOnly', readOnly)
          ..add('sonicAnalysis', sonicAnalysis)
          ..add('enrichmentWriteTags', enrichmentWriteTags)
          ..add('radioExternalArt', radioExternalArt)
          ..add('backupKeepCount', backupKeepCount)
          ..add('backupKeepBytes', backupKeepBytes)
          ..add('trashRetentionDays', trashRetentionDays)
          ..add('taskRetentionDays', taskRetentionDays))
        .toString();
  }
}

class AdminSettingsChangeBuilder
    implements Builder<AdminSettingsChange, AdminSettingsChangeBuilder> {
  _$AdminSettingsChange? _$v;

  bool? _signupEnabled;
  bool? get signupEnabled => _$this._signupEnabled;
  set signupEnabled(bool? signupEnabled) =>
      _$this._signupEnabled = signupEnabled;

  bool? _readOnly;
  bool? get readOnly => _$this._readOnly;
  set readOnly(bool? readOnly) => _$this._readOnly = readOnly;

  bool? _sonicAnalysis;
  bool? get sonicAnalysis => _$this._sonicAnalysis;
  set sonicAnalysis(bool? sonicAnalysis) =>
      _$this._sonicAnalysis = sonicAnalysis;

  bool? _enrichmentWriteTags;
  bool? get enrichmentWriteTags => _$this._enrichmentWriteTags;
  set enrichmentWriteTags(bool? enrichmentWriteTags) =>
      _$this._enrichmentWriteTags = enrichmentWriteTags;

  bool? _radioExternalArt;
  bool? get radioExternalArt => _$this._radioExternalArt;
  set radioExternalArt(bool? radioExternalArt) =>
      _$this._radioExternalArt = radioExternalArt;

  int? _backupKeepCount;
  int? get backupKeepCount => _$this._backupKeepCount;
  set backupKeepCount(int? backupKeepCount) =>
      _$this._backupKeepCount = backupKeepCount;

  int? _backupKeepBytes;
  int? get backupKeepBytes => _$this._backupKeepBytes;
  set backupKeepBytes(int? backupKeepBytes) =>
      _$this._backupKeepBytes = backupKeepBytes;

  int? _trashRetentionDays;
  int? get trashRetentionDays => _$this._trashRetentionDays;
  set trashRetentionDays(int? trashRetentionDays) =>
      _$this._trashRetentionDays = trashRetentionDays;

  int? _taskRetentionDays;
  int? get taskRetentionDays => _$this._taskRetentionDays;
  set taskRetentionDays(int? taskRetentionDays) =>
      _$this._taskRetentionDays = taskRetentionDays;

  AdminSettingsChangeBuilder() {
    AdminSettingsChange._defaults(this);
  }

  AdminSettingsChangeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _signupEnabled = $v.signupEnabled;
      _readOnly = $v.readOnly;
      _sonicAnalysis = $v.sonicAnalysis;
      _enrichmentWriteTags = $v.enrichmentWriteTags;
      _radioExternalArt = $v.radioExternalArt;
      _backupKeepCount = $v.backupKeepCount;
      _backupKeepBytes = $v.backupKeepBytes;
      _trashRetentionDays = $v.trashRetentionDays;
      _taskRetentionDays = $v.taskRetentionDays;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AdminSettingsChange other) {
    _$v = other as _$AdminSettingsChange;
  }

  @override
  void update(void Function(AdminSettingsChangeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AdminSettingsChange build() => _build();

  _$AdminSettingsChange _build() {
    final _$result =
        _$v ??
        _$AdminSettingsChange._(
          signupEnabled: signupEnabled,
          readOnly: readOnly,
          sonicAnalysis: sonicAnalysis,
          enrichmentWriteTags: enrichmentWriteTags,
          radioExternalArt: radioExternalArt,
          backupKeepCount: backupKeepCount,
          backupKeepBytes: backupKeepBytes,
          trashRetentionDays: trashRetentionDays,
          taskRetentionDays: taskRetentionDays,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
