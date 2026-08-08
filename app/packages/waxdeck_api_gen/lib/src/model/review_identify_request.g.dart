// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_identify_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ReviewIdentifyRequest extends ReviewIdentifyRequest {
  @override
  final String? artist;
  @override
  final String? album;
  @override
  final String? title;

  factory _$ReviewIdentifyRequest([
    void Function(ReviewIdentifyRequestBuilder)? updates,
  ]) => (ReviewIdentifyRequestBuilder()..update(updates))._build();

  _$ReviewIdentifyRequest._({this.artist, this.album, this.title}) : super._();
  @override
  ReviewIdentifyRequest rebuild(
    void Function(ReviewIdentifyRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  ReviewIdentifyRequestBuilder toBuilder() =>
      ReviewIdentifyRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReviewIdentifyRequest &&
        artist == other.artist &&
        album == other.album &&
        title == other.title;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, artist.hashCode);
    _$hash = $jc(_$hash, album.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReviewIdentifyRequest')
          ..add('artist', artist)
          ..add('album', album)
          ..add('title', title))
        .toString();
  }
}

class ReviewIdentifyRequestBuilder
    implements Builder<ReviewIdentifyRequest, ReviewIdentifyRequestBuilder> {
  _$ReviewIdentifyRequest? _$v;

  String? _artist;
  String? get artist => _$this._artist;
  set artist(String? artist) => _$this._artist = artist;

  String? _album;
  String? get album => _$this._album;
  set album(String? album) => _$this._album = album;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  ReviewIdentifyRequestBuilder() {
    ReviewIdentifyRequest._defaults(this);
  }

  ReviewIdentifyRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _artist = $v.artist;
      _album = $v.album;
      _title = $v.title;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReviewIdentifyRequest other) {
    _$v = other as _$ReviewIdentifyRequest;
  }

  @override
  void update(void Function(ReviewIdentifyRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReviewIdentifyRequest build() => _build();

  _$ReviewIdentifyRequest _build() {
    final _$result =
        _$v ??
        _$ReviewIdentifyRequest._(artist: artist, album: album, title: title);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
