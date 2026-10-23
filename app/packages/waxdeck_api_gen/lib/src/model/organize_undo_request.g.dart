// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'organize_undo_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OrganizeUndoRequest extends OrganizeUndoRequest {
  @override
  final String jobPid;

  factory _$OrganizeUndoRequest([
    void Function(OrganizeUndoRequestBuilder)? updates,
  ]) => (OrganizeUndoRequestBuilder()..update(updates))._build();

  _$OrganizeUndoRequest._({required this.jobPid}) : super._();
  @override
  OrganizeUndoRequest rebuild(
    void Function(OrganizeUndoRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  OrganizeUndoRequestBuilder toBuilder() =>
      OrganizeUndoRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OrganizeUndoRequest && jobPid == other.jobPid;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, jobPid.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'OrganizeUndoRequest',
    )..add('jobPid', jobPid)).toString();
  }
}

class OrganizeUndoRequestBuilder
    implements Builder<OrganizeUndoRequest, OrganizeUndoRequestBuilder> {
  _$OrganizeUndoRequest? _$v;

  String? _jobPid;
  String? get jobPid => _$this._jobPid;
  set jobPid(String? jobPid) => _$this._jobPid = jobPid;

  OrganizeUndoRequestBuilder() {
    OrganizeUndoRequest._defaults(this);
  }

  OrganizeUndoRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _jobPid = $v.jobPid;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OrganizeUndoRequest other) {
    _$v = other as _$OrganizeUndoRequest;
  }

  @override
  void update(void Function(OrganizeUndoRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OrganizeUndoRequest build() => _build();

  _$OrganizeUndoRequest _build() {
    final _$result =
        _$v ??
        _$OrganizeUndoRequest._(
          jobPid: BuiltValueNullFieldError.checkNotNull(
            jobPid,
            r'OrganizeUndoRequest',
            'jobPid',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
