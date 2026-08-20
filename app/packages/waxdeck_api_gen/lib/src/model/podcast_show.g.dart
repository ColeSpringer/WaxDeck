// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'podcast_show.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PodcastShow extends PodcastShow {
  @override
  final String pid;
  @override
  final String title;
  @override
  final String? author;
  @override
  final String? descriptionHtml;
  @override
  final String? feedUrl;
  @override
  final String? link;
  @override
  final String sourceType;
  @override
  final String? artUrl;
  @override
  final ArtSource? artSource;
  @override
  final int? episodeCount;
  @override
  final DateTime? lastPublishedAt;
  @override
  final bool? refreshDisabled;
  @override
  final bool? explicit;
  @override
  final PodcastFunding? funding;
  @override
  final String? medium;
  @override
  final BuiltList<FeedPerson>? persons;

  factory _$PodcastShow([void Function(PodcastShowBuilder)? updates]) =>
      (PodcastShowBuilder()..update(updates))._build();

  _$PodcastShow._({
    required this.pid,
    required this.title,
    this.author,
    this.descriptionHtml,
    this.feedUrl,
    this.link,
    required this.sourceType,
    this.artUrl,
    this.artSource,
    this.episodeCount,
    this.lastPublishedAt,
    this.refreshDisabled,
    this.explicit,
    this.funding,
    this.medium,
    this.persons,
  }) : super._();
  @override
  PodcastShow rebuild(void Function(PodcastShowBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PodcastShowBuilder toBuilder() => PodcastShowBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PodcastShow &&
        pid == other.pid &&
        title == other.title &&
        author == other.author &&
        descriptionHtml == other.descriptionHtml &&
        feedUrl == other.feedUrl &&
        link == other.link &&
        sourceType == other.sourceType &&
        artUrl == other.artUrl &&
        artSource == other.artSource &&
        episodeCount == other.episodeCount &&
        lastPublishedAt == other.lastPublishedAt &&
        refreshDisabled == other.refreshDisabled &&
        explicit == other.explicit &&
        funding == other.funding &&
        medium == other.medium &&
        persons == other.persons;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, author.hashCode);
    _$hash = $jc(_$hash, descriptionHtml.hashCode);
    _$hash = $jc(_$hash, feedUrl.hashCode);
    _$hash = $jc(_$hash, link.hashCode);
    _$hash = $jc(_$hash, sourceType.hashCode);
    _$hash = $jc(_$hash, artUrl.hashCode);
    _$hash = $jc(_$hash, artSource.hashCode);
    _$hash = $jc(_$hash, episodeCount.hashCode);
    _$hash = $jc(_$hash, lastPublishedAt.hashCode);
    _$hash = $jc(_$hash, refreshDisabled.hashCode);
    _$hash = $jc(_$hash, explicit.hashCode);
    _$hash = $jc(_$hash, funding.hashCode);
    _$hash = $jc(_$hash, medium.hashCode);
    _$hash = $jc(_$hash, persons.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PodcastShow')
          ..add('pid', pid)
          ..add('title', title)
          ..add('author', author)
          ..add('descriptionHtml', descriptionHtml)
          ..add('feedUrl', feedUrl)
          ..add('link', link)
          ..add('sourceType', sourceType)
          ..add('artUrl', artUrl)
          ..add('artSource', artSource)
          ..add('episodeCount', episodeCount)
          ..add('lastPublishedAt', lastPublishedAt)
          ..add('refreshDisabled', refreshDisabled)
          ..add('explicit', explicit)
          ..add('funding', funding)
          ..add('medium', medium)
          ..add('persons', persons))
        .toString();
  }
}

class PodcastShowBuilder implements Builder<PodcastShow, PodcastShowBuilder> {
  _$PodcastShow? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _author;
  String? get author => _$this._author;
  set author(String? author) => _$this._author = author;

  String? _descriptionHtml;
  String? get descriptionHtml => _$this._descriptionHtml;
  set descriptionHtml(String? descriptionHtml) =>
      _$this._descriptionHtml = descriptionHtml;

  String? _feedUrl;
  String? get feedUrl => _$this._feedUrl;
  set feedUrl(String? feedUrl) => _$this._feedUrl = feedUrl;

  String? _link;
  String? get link => _$this._link;
  set link(String? link) => _$this._link = link;

  String? _sourceType;
  String? get sourceType => _$this._sourceType;
  set sourceType(String? sourceType) => _$this._sourceType = sourceType;

  String? _artUrl;
  String? get artUrl => _$this._artUrl;
  set artUrl(String? artUrl) => _$this._artUrl = artUrl;

  ArtSourceBuilder? _artSource;
  ArtSourceBuilder get artSource => _$this._artSource ??= ArtSourceBuilder();
  set artSource(ArtSourceBuilder? artSource) => _$this._artSource = artSource;

  int? _episodeCount;
  int? get episodeCount => _$this._episodeCount;
  set episodeCount(int? episodeCount) => _$this._episodeCount = episodeCount;

  DateTime? _lastPublishedAt;
  DateTime? get lastPublishedAt => _$this._lastPublishedAt;
  set lastPublishedAt(DateTime? lastPublishedAt) =>
      _$this._lastPublishedAt = lastPublishedAt;

  bool? _refreshDisabled;
  bool? get refreshDisabled => _$this._refreshDisabled;
  set refreshDisabled(bool? refreshDisabled) =>
      _$this._refreshDisabled = refreshDisabled;

  bool? _explicit;
  bool? get explicit => _$this._explicit;
  set explicit(bool? explicit) => _$this._explicit = explicit;

  PodcastFundingBuilder? _funding;
  PodcastFundingBuilder get funding =>
      _$this._funding ??= PodcastFundingBuilder();
  set funding(PodcastFundingBuilder? funding) => _$this._funding = funding;

  String? _medium;
  String? get medium => _$this._medium;
  set medium(String? medium) => _$this._medium = medium;

  ListBuilder<FeedPerson>? _persons;
  ListBuilder<FeedPerson> get persons =>
      _$this._persons ??= ListBuilder<FeedPerson>();
  set persons(ListBuilder<FeedPerson>? persons) => _$this._persons = persons;

  PodcastShowBuilder() {
    PodcastShow._defaults(this);
  }

  PodcastShowBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _title = $v.title;
      _author = $v.author;
      _descriptionHtml = $v.descriptionHtml;
      _feedUrl = $v.feedUrl;
      _link = $v.link;
      _sourceType = $v.sourceType;
      _artUrl = $v.artUrl;
      _artSource = $v.artSource?.toBuilder();
      _episodeCount = $v.episodeCount;
      _lastPublishedAt = $v.lastPublishedAt;
      _refreshDisabled = $v.refreshDisabled;
      _explicit = $v.explicit;
      _funding = $v.funding?.toBuilder();
      _medium = $v.medium;
      _persons = $v.persons?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PodcastShow other) {
    _$v = other as _$PodcastShow;
  }

  @override
  void update(void Function(PodcastShowBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PodcastShow build() => _build();

  _$PodcastShow _build() {
    _$PodcastShow _$result;
    try {
      _$result =
          _$v ??
          _$PodcastShow._(
            pid: BuiltValueNullFieldError.checkNotNull(
              pid,
              r'PodcastShow',
              'pid',
            ),
            title: BuiltValueNullFieldError.checkNotNull(
              title,
              r'PodcastShow',
              'title',
            ),
            author: author,
            descriptionHtml: descriptionHtml,
            feedUrl: feedUrl,
            link: link,
            sourceType: BuiltValueNullFieldError.checkNotNull(
              sourceType,
              r'PodcastShow',
              'sourceType',
            ),
            artUrl: artUrl,
            artSource: _artSource?.build(),
            episodeCount: episodeCount,
            lastPublishedAt: lastPublishedAt,
            refreshDisabled: refreshDisabled,
            explicit: explicit,
            funding: _funding?.build(),
            medium: medium,
            persons: _persons?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'artSource';
        _artSource?.build();

        _$failedField = 'funding';
        _funding?.build();

        _$failedField = 'persons';
        _persons?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PodcastShow',
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
