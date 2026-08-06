// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'podcast_directory_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PodcastDirectoryEntry extends PodcastDirectoryEntry {
  @override
  final String name;
  @override
  final String feedUrl;
  @override
  final String? author;
  @override
  final String? artworkUrl;
  @override
  final String? genre;
  @override
  final int? episodeCount;

  factory _$PodcastDirectoryEntry([
    void Function(PodcastDirectoryEntryBuilder)? updates,
  ]) => (PodcastDirectoryEntryBuilder()..update(updates))._build();

  _$PodcastDirectoryEntry._({
    required this.name,
    required this.feedUrl,
    this.author,
    this.artworkUrl,
    this.genre,
    this.episodeCount,
  }) : super._();
  @override
  PodcastDirectoryEntry rebuild(
    void Function(PodcastDirectoryEntryBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PodcastDirectoryEntryBuilder toBuilder() =>
      PodcastDirectoryEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PodcastDirectoryEntry &&
        name == other.name &&
        feedUrl == other.feedUrl &&
        author == other.author &&
        artworkUrl == other.artworkUrl &&
        genre == other.genre &&
        episodeCount == other.episodeCount;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, feedUrl.hashCode);
    _$hash = $jc(_$hash, author.hashCode);
    _$hash = $jc(_$hash, artworkUrl.hashCode);
    _$hash = $jc(_$hash, genre.hashCode);
    _$hash = $jc(_$hash, episodeCount.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PodcastDirectoryEntry')
          ..add('name', name)
          ..add('feedUrl', feedUrl)
          ..add('author', author)
          ..add('artworkUrl', artworkUrl)
          ..add('genre', genre)
          ..add('episodeCount', episodeCount))
        .toString();
  }
}

class PodcastDirectoryEntryBuilder
    implements Builder<PodcastDirectoryEntry, PodcastDirectoryEntryBuilder> {
  _$PodcastDirectoryEntry? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _feedUrl;
  String? get feedUrl => _$this._feedUrl;
  set feedUrl(String? feedUrl) => _$this._feedUrl = feedUrl;

  String? _author;
  String? get author => _$this._author;
  set author(String? author) => _$this._author = author;

  String? _artworkUrl;
  String? get artworkUrl => _$this._artworkUrl;
  set artworkUrl(String? artworkUrl) => _$this._artworkUrl = artworkUrl;

  String? _genre;
  String? get genre => _$this._genre;
  set genre(String? genre) => _$this._genre = genre;

  int? _episodeCount;
  int? get episodeCount => _$this._episodeCount;
  set episodeCount(int? episodeCount) => _$this._episodeCount = episodeCount;

  PodcastDirectoryEntryBuilder() {
    PodcastDirectoryEntry._defaults(this);
  }

  PodcastDirectoryEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _feedUrl = $v.feedUrl;
      _author = $v.author;
      _artworkUrl = $v.artworkUrl;
      _genre = $v.genre;
      _episodeCount = $v.episodeCount;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PodcastDirectoryEntry other) {
    _$v = other as _$PodcastDirectoryEntry;
  }

  @override
  void update(void Function(PodcastDirectoryEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PodcastDirectoryEntry build() => _build();

  _$PodcastDirectoryEntry _build() {
    final _$result =
        _$v ??
        _$PodcastDirectoryEntry._(
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'PodcastDirectoryEntry',
            'name',
          ),
          feedUrl: BuiltValueNullFieldError.checkNotNull(
            feedUrl,
            r'PodcastDirectoryEntry',
            'feedUrl',
          ),
          author: author,
          artworkUrl: artworkUrl,
          genre: genre,
          episodeCount: episodeCount,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
