// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_detail.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BookDetail extends BookDetail {
  @override
  final String pid;
  @override
  final String title;
  @override
  final String? subtitle;
  @override
  final BuiltList<String> authors;
  @override
  final BuiltList<String> narrators;
  @override
  final String? series;
  @override
  final String? seriesSequence;
  @override
  final String? publisher;
  @override
  final String? asin;
  @override
  final String? isbn;
  @override
  final String? edition;
  @override
  final bool? abridged;
  @override
  final String? descriptionHtml;
  @override
  final int durationMs;
  @override
  final String? artUrl;
  @override
  final BuiltList<ChapterMark> chapters;
  @override
  final BuiltList<BookPart> parts;
  @override
  final BookSettings? settings;

  factory _$BookDetail([void Function(BookDetailBuilder)? updates]) =>
      (BookDetailBuilder()..update(updates))._build();

  _$BookDetail._({
    required this.pid,
    required this.title,
    this.subtitle,
    required this.authors,
    required this.narrators,
    this.series,
    this.seriesSequence,
    this.publisher,
    this.asin,
    this.isbn,
    this.edition,
    this.abridged,
    this.descriptionHtml,
    required this.durationMs,
    this.artUrl,
    required this.chapters,
    required this.parts,
    this.settings,
  }) : super._();
  @override
  BookDetail rebuild(void Function(BookDetailBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookDetailBuilder toBuilder() => BookDetailBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookDetail &&
        pid == other.pid &&
        title == other.title &&
        subtitle == other.subtitle &&
        authors == other.authors &&
        narrators == other.narrators &&
        series == other.series &&
        seriesSequence == other.seriesSequence &&
        publisher == other.publisher &&
        asin == other.asin &&
        isbn == other.isbn &&
        edition == other.edition &&
        abridged == other.abridged &&
        descriptionHtml == other.descriptionHtml &&
        durationMs == other.durationMs &&
        artUrl == other.artUrl &&
        chapters == other.chapters &&
        parts == other.parts &&
        settings == other.settings;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, subtitle.hashCode);
    _$hash = $jc(_$hash, authors.hashCode);
    _$hash = $jc(_$hash, narrators.hashCode);
    _$hash = $jc(_$hash, series.hashCode);
    _$hash = $jc(_$hash, seriesSequence.hashCode);
    _$hash = $jc(_$hash, publisher.hashCode);
    _$hash = $jc(_$hash, asin.hashCode);
    _$hash = $jc(_$hash, isbn.hashCode);
    _$hash = $jc(_$hash, edition.hashCode);
    _$hash = $jc(_$hash, abridged.hashCode);
    _$hash = $jc(_$hash, descriptionHtml.hashCode);
    _$hash = $jc(_$hash, durationMs.hashCode);
    _$hash = $jc(_$hash, artUrl.hashCode);
    _$hash = $jc(_$hash, chapters.hashCode);
    _$hash = $jc(_$hash, parts.hashCode);
    _$hash = $jc(_$hash, settings.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookDetail')
          ..add('pid', pid)
          ..add('title', title)
          ..add('subtitle', subtitle)
          ..add('authors', authors)
          ..add('narrators', narrators)
          ..add('series', series)
          ..add('seriesSequence', seriesSequence)
          ..add('publisher', publisher)
          ..add('asin', asin)
          ..add('isbn', isbn)
          ..add('edition', edition)
          ..add('abridged', abridged)
          ..add('descriptionHtml', descriptionHtml)
          ..add('durationMs', durationMs)
          ..add('artUrl', artUrl)
          ..add('chapters', chapters)
          ..add('parts', parts)
          ..add('settings', settings))
        .toString();
  }
}

class BookDetailBuilder implements Builder<BookDetail, BookDetailBuilder> {
  _$BookDetail? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _subtitle;
  String? get subtitle => _$this._subtitle;
  set subtitle(String? subtitle) => _$this._subtitle = subtitle;

  ListBuilder<String>? _authors;
  ListBuilder<String> get authors => _$this._authors ??= ListBuilder<String>();
  set authors(ListBuilder<String>? authors) => _$this._authors = authors;

  ListBuilder<String>? _narrators;
  ListBuilder<String> get narrators =>
      _$this._narrators ??= ListBuilder<String>();
  set narrators(ListBuilder<String>? narrators) =>
      _$this._narrators = narrators;

  String? _series;
  String? get series => _$this._series;
  set series(String? series) => _$this._series = series;

  String? _seriesSequence;
  String? get seriesSequence => _$this._seriesSequence;
  set seriesSequence(String? seriesSequence) =>
      _$this._seriesSequence = seriesSequence;

  String? _publisher;
  String? get publisher => _$this._publisher;
  set publisher(String? publisher) => _$this._publisher = publisher;

  String? _asin;
  String? get asin => _$this._asin;
  set asin(String? asin) => _$this._asin = asin;

  String? _isbn;
  String? get isbn => _$this._isbn;
  set isbn(String? isbn) => _$this._isbn = isbn;

  String? _edition;
  String? get edition => _$this._edition;
  set edition(String? edition) => _$this._edition = edition;

  bool? _abridged;
  bool? get abridged => _$this._abridged;
  set abridged(bool? abridged) => _$this._abridged = abridged;

  String? _descriptionHtml;
  String? get descriptionHtml => _$this._descriptionHtml;
  set descriptionHtml(String? descriptionHtml) =>
      _$this._descriptionHtml = descriptionHtml;

  int? _durationMs;
  int? get durationMs => _$this._durationMs;
  set durationMs(int? durationMs) => _$this._durationMs = durationMs;

  String? _artUrl;
  String? get artUrl => _$this._artUrl;
  set artUrl(String? artUrl) => _$this._artUrl = artUrl;

  ListBuilder<ChapterMark>? _chapters;
  ListBuilder<ChapterMark> get chapters =>
      _$this._chapters ??= ListBuilder<ChapterMark>();
  set chapters(ListBuilder<ChapterMark>? chapters) =>
      _$this._chapters = chapters;

  ListBuilder<BookPart>? _parts;
  ListBuilder<BookPart> get parts => _$this._parts ??= ListBuilder<BookPart>();
  set parts(ListBuilder<BookPart>? parts) => _$this._parts = parts;

  BookSettingsBuilder? _settings;
  BookSettingsBuilder get settings =>
      _$this._settings ??= BookSettingsBuilder();
  set settings(BookSettingsBuilder? settings) => _$this._settings = settings;

  BookDetailBuilder() {
    BookDetail._defaults(this);
  }

  BookDetailBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _title = $v.title;
      _subtitle = $v.subtitle;
      _authors = $v.authors.toBuilder();
      _narrators = $v.narrators.toBuilder();
      _series = $v.series;
      _seriesSequence = $v.seriesSequence;
      _publisher = $v.publisher;
      _asin = $v.asin;
      _isbn = $v.isbn;
      _edition = $v.edition;
      _abridged = $v.abridged;
      _descriptionHtml = $v.descriptionHtml;
      _durationMs = $v.durationMs;
      _artUrl = $v.artUrl;
      _chapters = $v.chapters.toBuilder();
      _parts = $v.parts.toBuilder();
      _settings = $v.settings?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookDetail other) {
    _$v = other as _$BookDetail;
  }

  @override
  void update(void Function(BookDetailBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookDetail build() => _build();

  _$BookDetail _build() {
    _$BookDetail _$result;
    try {
      _$result =
          _$v ??
          _$BookDetail._(
            pid: BuiltValueNullFieldError.checkNotNull(
              pid,
              r'BookDetail',
              'pid',
            ),
            title: BuiltValueNullFieldError.checkNotNull(
              title,
              r'BookDetail',
              'title',
            ),
            subtitle: subtitle,
            authors: authors.build(),
            narrators: narrators.build(),
            series: series,
            seriesSequence: seriesSequence,
            publisher: publisher,
            asin: asin,
            isbn: isbn,
            edition: edition,
            abridged: abridged,
            descriptionHtml: descriptionHtml,
            durationMs: BuiltValueNullFieldError.checkNotNull(
              durationMs,
              r'BookDetail',
              'durationMs',
            ),
            artUrl: artUrl,
            chapters: chapters.build(),
            parts: parts.build(),
            settings: _settings?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'authors';
        authors.build();
        _$failedField = 'narrators';
        narrators.build();

        _$failedField = 'chapters';
        chapters.build();
        _$failedField = 'parts';
        parts.build();
        _$failedField = 'settings';
        _settings?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'BookDetail',
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
