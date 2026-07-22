// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_batch.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UploadBatch extends UploadBatch {
  @override
  final String id;
  @override
  final UploadGrouping grouping;
  @override
  final MediaType mediaType;
  @override
  final String? libraryPid;
  @override
  final String state;
  @override
  final BuiltList<String> reviewEntryIds;
  @override
  final DateTime createdAt;
  @override
  final DateTime expiresAt;

  factory _$UploadBatch([void Function(UploadBatchBuilder)? updates]) =>
      (UploadBatchBuilder()..update(updates))._build();

  _$UploadBatch._({
    required this.id,
    required this.grouping,
    required this.mediaType,
    this.libraryPid,
    required this.state,
    required this.reviewEntryIds,
    required this.createdAt,
    required this.expiresAt,
  }) : super._();
  @override
  UploadBatch rebuild(void Function(UploadBatchBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UploadBatchBuilder toBuilder() => UploadBatchBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UploadBatch &&
        id == other.id &&
        grouping == other.grouping &&
        mediaType == other.mediaType &&
        libraryPid == other.libraryPid &&
        state == other.state &&
        reviewEntryIds == other.reviewEntryIds &&
        createdAt == other.createdAt &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, grouping.hashCode);
    _$hash = $jc(_$hash, mediaType.hashCode);
    _$hash = $jc(_$hash, libraryPid.hashCode);
    _$hash = $jc(_$hash, state.hashCode);
    _$hash = $jc(_$hash, reviewEntryIds.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UploadBatch')
          ..add('id', id)
          ..add('grouping', grouping)
          ..add('mediaType', mediaType)
          ..add('libraryPid', libraryPid)
          ..add('state', state)
          ..add('reviewEntryIds', reviewEntryIds)
          ..add('createdAt', createdAt)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class UploadBatchBuilder implements Builder<UploadBatch, UploadBatchBuilder> {
  _$UploadBatch? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  UploadGrouping? _grouping;
  UploadGrouping? get grouping => _$this._grouping;
  set grouping(UploadGrouping? grouping) => _$this._grouping = grouping;

  MediaType? _mediaType;
  MediaType? get mediaType => _$this._mediaType;
  set mediaType(MediaType? mediaType) => _$this._mediaType = mediaType;

  String? _libraryPid;
  String? get libraryPid => _$this._libraryPid;
  set libraryPid(String? libraryPid) => _$this._libraryPid = libraryPid;

  String? _state;
  String? get state => _$this._state;
  set state(String? state) => _$this._state = state;

  ListBuilder<String>? _reviewEntryIds;
  ListBuilder<String> get reviewEntryIds =>
      _$this._reviewEntryIds ??= ListBuilder<String>();
  set reviewEntryIds(ListBuilder<String>? reviewEntryIds) =>
      _$this._reviewEntryIds = reviewEntryIds;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  UploadBatchBuilder() {
    UploadBatch._defaults(this);
  }

  UploadBatchBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _grouping = $v.grouping;
      _mediaType = $v.mediaType;
      _libraryPid = $v.libraryPid;
      _state = $v.state;
      _reviewEntryIds = $v.reviewEntryIds.toBuilder();
      _createdAt = $v.createdAt;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UploadBatch other) {
    _$v = other as _$UploadBatch;
  }

  @override
  void update(void Function(UploadBatchBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UploadBatch build() => _build();

  _$UploadBatch _build() {
    _$UploadBatch _$result;
    try {
      _$result =
          _$v ??
          _$UploadBatch._(
            id: BuiltValueNullFieldError.checkNotNull(id, r'UploadBatch', 'id'),
            grouping: BuiltValueNullFieldError.checkNotNull(
              grouping,
              r'UploadBatch',
              'grouping',
            ),
            mediaType: BuiltValueNullFieldError.checkNotNull(
              mediaType,
              r'UploadBatch',
              'mediaType',
            ),
            libraryPid: libraryPid,
            state: BuiltValueNullFieldError.checkNotNull(
              state,
              r'UploadBatch',
              'state',
            ),
            reviewEntryIds: reviewEntryIds.build(),
            createdAt: BuiltValueNullFieldError.checkNotNull(
              createdAt,
              r'UploadBatch',
              'createdAt',
            ),
            expiresAt: BuiltValueNullFieldError.checkNotNull(
              expiresAt,
              r'UploadBatch',
              'expiresAt',
            ),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'reviewEntryIds';
        reviewEntryIds.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'UploadBatch',
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
