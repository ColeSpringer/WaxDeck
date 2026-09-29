// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_issue_detail.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$HealthIssueDetail extends HealthIssueDetail {
  @override
  final int? headerMs;
  @override
  final int? decodedMs;
  @override
  final int? partIndex;
  @override
  final bool? wholeFile;

  factory _$HealthIssueDetail([
    void Function(HealthIssueDetailBuilder)? updates,
  ]) => (HealthIssueDetailBuilder()..update(updates))._build();

  _$HealthIssueDetail._({
    this.headerMs,
    this.decodedMs,
    this.partIndex,
    this.wholeFile,
  }) : super._();
  @override
  HealthIssueDetail rebuild(void Function(HealthIssueDetailBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HealthIssueDetailBuilder toBuilder() =>
      HealthIssueDetailBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HealthIssueDetail &&
        headerMs == other.headerMs &&
        decodedMs == other.decodedMs &&
        partIndex == other.partIndex &&
        wholeFile == other.wholeFile;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, headerMs.hashCode);
    _$hash = $jc(_$hash, decodedMs.hashCode);
    _$hash = $jc(_$hash, partIndex.hashCode);
    _$hash = $jc(_$hash, wholeFile.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HealthIssueDetail')
          ..add('headerMs', headerMs)
          ..add('decodedMs', decodedMs)
          ..add('partIndex', partIndex)
          ..add('wholeFile', wholeFile))
        .toString();
  }
}

class HealthIssueDetailBuilder
    implements Builder<HealthIssueDetail, HealthIssueDetailBuilder> {
  _$HealthIssueDetail? _$v;

  int? _headerMs;
  int? get headerMs => _$this._headerMs;
  set headerMs(int? headerMs) => _$this._headerMs = headerMs;

  int? _decodedMs;
  int? get decodedMs => _$this._decodedMs;
  set decodedMs(int? decodedMs) => _$this._decodedMs = decodedMs;

  int? _partIndex;
  int? get partIndex => _$this._partIndex;
  set partIndex(int? partIndex) => _$this._partIndex = partIndex;

  bool? _wholeFile;
  bool? get wholeFile => _$this._wholeFile;
  set wholeFile(bool? wholeFile) => _$this._wholeFile = wholeFile;

  HealthIssueDetailBuilder() {
    HealthIssueDetail._defaults(this);
  }

  HealthIssueDetailBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _headerMs = $v.headerMs;
      _decodedMs = $v.decodedMs;
      _partIndex = $v.partIndex;
      _wholeFile = $v.wholeFile;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HealthIssueDetail other) {
    _$v = other as _$HealthIssueDetail;
  }

  @override
  void update(void Function(HealthIssueDetailBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HealthIssueDetail build() => _build();

  _$HealthIssueDetail _build() {
    final _$result =
        _$v ??
        _$HealthIssueDetail._(
          headerMs: headerMs,
          decodedMs: decodedMs,
          partIndex: partIndex,
          wholeFile: wholeFile,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
