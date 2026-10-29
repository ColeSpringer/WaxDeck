// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'm3u_preview_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$M3uPreviewRequest extends M3uPreviewRequest {
  @override
  final String content;

  factory _$M3uPreviewRequest([
    void Function(M3uPreviewRequestBuilder)? updates,
  ]) => (M3uPreviewRequestBuilder()..update(updates))._build();

  _$M3uPreviewRequest._({required this.content}) : super._();
  @override
  M3uPreviewRequest rebuild(void Function(M3uPreviewRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  M3uPreviewRequestBuilder toBuilder() =>
      M3uPreviewRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is M3uPreviewRequest && content == other.content;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, content.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'M3uPreviewRequest',
    )..add('content', content)).toString();
  }
}

class M3uPreviewRequestBuilder
    implements Builder<M3uPreviewRequest, M3uPreviewRequestBuilder> {
  _$M3uPreviewRequest? _$v;

  String? _content;
  String? get content => _$this._content;
  set content(String? content) => _$this._content = content;

  M3uPreviewRequestBuilder() {
    M3uPreviewRequest._defaults(this);
  }

  M3uPreviewRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _content = $v.content;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(M3uPreviewRequest other) {
    _$v = other as _$M3uPreviewRequest;
  }

  @override
  void update(void Function(M3uPreviewRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  M3uPreviewRequest build() => _build();

  _$M3uPreviewRequest _build() {
    final _$result =
        _$v ??
        _$M3uPreviewRequest._(
          content: BuiltValueNullFieldError.checkNotNull(
            content,
            r'M3uPreviewRequest',
            'content',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
