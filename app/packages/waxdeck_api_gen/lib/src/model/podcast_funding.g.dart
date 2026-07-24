// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'podcast_funding.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PodcastFunding extends PodcastFunding {
  @override
  final String url;
  @override
  final String? message;

  factory _$PodcastFunding([void Function(PodcastFundingBuilder)? updates]) =>
      (PodcastFundingBuilder()..update(updates))._build();

  _$PodcastFunding._({required this.url, this.message}) : super._();
  @override
  PodcastFunding rebuild(void Function(PodcastFundingBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PodcastFundingBuilder toBuilder() => PodcastFundingBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PodcastFunding &&
        url == other.url &&
        message == other.message;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PodcastFunding')
          ..add('url', url)
          ..add('message', message))
        .toString();
  }
}

class PodcastFundingBuilder
    implements Builder<PodcastFunding, PodcastFundingBuilder> {
  _$PodcastFunding? _$v;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  PodcastFundingBuilder() {
    PodcastFunding._defaults(this);
  }

  PodcastFundingBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _url = $v.url;
      _message = $v.message;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PodcastFunding other) {
    _$v = other as _$PodcastFunding;
  }

  @override
  void update(void Function(PodcastFundingBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PodcastFunding build() => _build();

  _$PodcastFunding _build() {
    final _$result =
        _$v ??
        _$PodcastFunding._(
          url: BuiltValueNullFieldError.checkNotNull(
            url,
            r'PodcastFunding',
            'url',
          ),
          message: message,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
