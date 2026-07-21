// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UploadPage extends UploadPage {
  @override
  final BuiltList<Upload> uploads;
  @override
  final String? nextCursor;

  factory _$UploadPage([void Function(UploadPageBuilder)? updates]) =>
      (UploadPageBuilder()..update(updates))._build();

  _$UploadPage._({required this.uploads, this.nextCursor}) : super._();
  @override
  UploadPage rebuild(void Function(UploadPageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UploadPageBuilder toBuilder() => UploadPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UploadPage &&
        uploads == other.uploads &&
        nextCursor == other.nextCursor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, uploads.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UploadPage')
          ..add('uploads', uploads)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class UploadPageBuilder implements Builder<UploadPage, UploadPageBuilder> {
  _$UploadPage? _$v;

  ListBuilder<Upload>? _uploads;
  ListBuilder<Upload> get uploads => _$this._uploads ??= ListBuilder<Upload>();
  set uploads(ListBuilder<Upload>? uploads) => _$this._uploads = uploads;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  UploadPageBuilder() {
    UploadPage._defaults(this);
  }

  UploadPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _uploads = $v.uploads.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UploadPage other) {
    _$v = other as _$UploadPage;
  }

  @override
  void update(void Function(UploadPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UploadPage build() => _build();

  _$UploadPage _build() {
    _$UploadPage _$result;
    try {
      _$result =
          _$v ??
          _$UploadPage._(uploads: uploads.build(), nextCursor: nextCursor);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'uploads';
        uploads.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'UploadPage',
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
