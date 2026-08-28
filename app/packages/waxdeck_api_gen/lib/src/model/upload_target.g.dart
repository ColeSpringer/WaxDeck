// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_target.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UploadTarget extends UploadTarget {
  @override
  final String pid;
  @override
  final String name;
  @override
  final BuiltList<MediaType> mediaTypes;
  @override
  final bool managed;

  factory _$UploadTarget([void Function(UploadTargetBuilder)? updates]) =>
      (UploadTargetBuilder()..update(updates))._build();

  _$UploadTarget._({
    required this.pid,
    required this.name,
    required this.mediaTypes,
    required this.managed,
  }) : super._();
  @override
  UploadTarget rebuild(void Function(UploadTargetBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UploadTargetBuilder toBuilder() => UploadTargetBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UploadTarget &&
        pid == other.pid &&
        name == other.name &&
        mediaTypes == other.mediaTypes &&
        managed == other.managed;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, mediaTypes.hashCode);
    _$hash = $jc(_$hash, managed.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UploadTarget')
          ..add('pid', pid)
          ..add('name', name)
          ..add('mediaTypes', mediaTypes)
          ..add('managed', managed))
        .toString();
  }
}

class UploadTargetBuilder
    implements Builder<UploadTarget, UploadTargetBuilder> {
  _$UploadTarget? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  ListBuilder<MediaType>? _mediaTypes;
  ListBuilder<MediaType> get mediaTypes =>
      _$this._mediaTypes ??= ListBuilder<MediaType>();
  set mediaTypes(ListBuilder<MediaType>? mediaTypes) =>
      _$this._mediaTypes = mediaTypes;

  bool? _managed;
  bool? get managed => _$this._managed;
  set managed(bool? managed) => _$this._managed = managed;

  UploadTargetBuilder() {
    UploadTarget._defaults(this);
  }

  UploadTargetBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _name = $v.name;
      _mediaTypes = $v.mediaTypes.toBuilder();
      _managed = $v.managed;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UploadTarget other) {
    _$v = other as _$UploadTarget;
  }

  @override
  void update(void Function(UploadTargetBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UploadTarget build() => _build();

  _$UploadTarget _build() {
    _$UploadTarget _$result;
    try {
      _$result =
          _$v ??
          _$UploadTarget._(
            pid: BuiltValueNullFieldError.checkNotNull(
              pid,
              r'UploadTarget',
              'pid',
            ),
            name: BuiltValueNullFieldError.checkNotNull(
              name,
              r'UploadTarget',
              'name',
            ),
            mediaTypes: mediaTypes.build(),
            managed: BuiltValueNullFieldError.checkNotNull(
              managed,
              r'UploadTarget',
              'managed',
            ),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'mediaTypes';
        mediaTypes.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'UploadTarget',
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
