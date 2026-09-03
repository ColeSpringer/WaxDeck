// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'detach_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DetachResult extends DetachResult {
  @override
  final String itemPid;
  @override
  final String oldAlbumPid;
  @override
  final String? newAlbumPid;
  @override
  final String? newReleaseGroupPid;
  @override
  final BuiltList<WriteBackFailure>? failures;

  factory _$DetachResult([void Function(DetachResultBuilder)? updates]) =>
      (DetachResultBuilder()..update(updates))._build();

  _$DetachResult._({
    required this.itemPid,
    required this.oldAlbumPid,
    this.newAlbumPid,
    this.newReleaseGroupPid,
    this.failures,
  }) : super._();
  @override
  DetachResult rebuild(void Function(DetachResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DetachResultBuilder toBuilder() => DetachResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DetachResult &&
        itemPid == other.itemPid &&
        oldAlbumPid == other.oldAlbumPid &&
        newAlbumPid == other.newAlbumPid &&
        newReleaseGroupPid == other.newReleaseGroupPid &&
        failures == other.failures;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, itemPid.hashCode);
    _$hash = $jc(_$hash, oldAlbumPid.hashCode);
    _$hash = $jc(_$hash, newAlbumPid.hashCode);
    _$hash = $jc(_$hash, newReleaseGroupPid.hashCode);
    _$hash = $jc(_$hash, failures.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DetachResult')
          ..add('itemPid', itemPid)
          ..add('oldAlbumPid', oldAlbumPid)
          ..add('newAlbumPid', newAlbumPid)
          ..add('newReleaseGroupPid', newReleaseGroupPid)
          ..add('failures', failures))
        .toString();
  }
}

class DetachResultBuilder
    implements Builder<DetachResult, DetachResultBuilder> {
  _$DetachResult? _$v;

  String? _itemPid;
  String? get itemPid => _$this._itemPid;
  set itemPid(String? itemPid) => _$this._itemPid = itemPid;

  String? _oldAlbumPid;
  String? get oldAlbumPid => _$this._oldAlbumPid;
  set oldAlbumPid(String? oldAlbumPid) => _$this._oldAlbumPid = oldAlbumPid;

  String? _newAlbumPid;
  String? get newAlbumPid => _$this._newAlbumPid;
  set newAlbumPid(String? newAlbumPid) => _$this._newAlbumPid = newAlbumPid;

  String? _newReleaseGroupPid;
  String? get newReleaseGroupPid => _$this._newReleaseGroupPid;
  set newReleaseGroupPid(String? newReleaseGroupPid) =>
      _$this._newReleaseGroupPid = newReleaseGroupPid;

  ListBuilder<WriteBackFailure>? _failures;
  ListBuilder<WriteBackFailure> get failures =>
      _$this._failures ??= ListBuilder<WriteBackFailure>();
  set failures(ListBuilder<WriteBackFailure>? failures) =>
      _$this._failures = failures;

  DetachResultBuilder() {
    DetachResult._defaults(this);
  }

  DetachResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _itemPid = $v.itemPid;
      _oldAlbumPid = $v.oldAlbumPid;
      _newAlbumPid = $v.newAlbumPid;
      _newReleaseGroupPid = $v.newReleaseGroupPid;
      _failures = $v.failures?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DetachResult other) {
    _$v = other as _$DetachResult;
  }

  @override
  void update(void Function(DetachResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DetachResult build() => _build();

  _$DetachResult _build() {
    _$DetachResult _$result;
    try {
      _$result =
          _$v ??
          _$DetachResult._(
            itemPid: BuiltValueNullFieldError.checkNotNull(
              itemPid,
              r'DetachResult',
              'itemPid',
            ),
            oldAlbumPid: BuiltValueNullFieldError.checkNotNull(
              oldAlbumPid,
              r'DetachResult',
              'oldAlbumPid',
            ),
            newAlbumPid: newAlbumPid,
            newReleaseGroupPid: newReleaseGroupPid,
            failures: _failures?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'failures';
        _failures?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'DetachResult',
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
