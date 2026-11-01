import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/art_source_label.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

ItemMetadata _holding(
  String pid,
  String value, {
  FieldProvenance? row,
  MediaType mediaType = MediaType.music,
}) => ItemMetadata(
  pid: pid,
  mediaType: mediaType,
  fields: {'genre': value},
  provenance: [?row],
);

FieldProvenance _row(String source, {String? provider}) => FieldProvenance(
  field: 'genre',
  source: source,
  provider: provider,
  locked: true,
);

void main() {
  final l10n = AppLocalizationsEn();

  group('sharedFieldSourceName', () {
    test('a value every item had set by hand reads as yours', () {
      expect(
        sharedFieldSourceName(l10n, [
          _holding('tr-1', 'Jazz', row: _row('user')),
          _holding('tr-2', 'Jazz', row: _row('user')),
        ], 'genre'),
        'you',
      );
    });

    test('a value every item took from its file reads as the tags', () {
      expect(
        sharedFieldSourceName(l10n, [
          _holding('tr-1', 'Jazz'),
          _holding('tr-2', 'Jazz'),
        ], 'genre'),
        'tags',
      );
    });

    test('episodes with no row read as the feed', () {
      expect(
        sharedFieldSourceName(l10n, [
          _holding('ep-1', 'News', mediaType: MediaType.podcast),
          _holding('ep-2', 'News', mediaType: MediaType.podcast),
        ], 'genre'),
        'the feed',
      );
    });

    test('one provider for every item is named', () {
      expect(
        sharedFieldSourceName(l10n, [
          _holding(
            'tr-1',
            'Jazz',
            row: _row('enrichment', provider: 'musicbrainz'),
          ),
          _holding(
            'tr-2',
            'Jazz',
            row: _row('enrichment', provider: 'musicbrainz'),
          ),
        ], 'genre'),
        'MusicBrainz',
      );
    });

    test('sources that differ credit no one', () {
      expect(
        sharedFieldSourceName(l10n, [
          _holding('tr-1', 'Jazz', row: _row('user')),
          _holding('tr-2', 'Jazz'),
        ], 'genre'),
        isNull,
      );
      expect(
        sharedFieldSourceName(l10n, [
          _holding(
            'tr-1',
            'Jazz',
            row: _row('enrichment', provider: 'musicbrainz'),
          ),
          _holding(
            'tr-2',
            'Jazz',
            row: _row('enrichment', provider: 'discogs'),
          ),
        ], 'genre'),
        isNull,
      );
    });

    test('an empty shared value with no row has nothing to credit', () {
      expect(
        sharedFieldSourceName(l10n, [
          _holding('tr-1', ''),
          _holding('tr-2', ''),
        ], 'genre'),
        isNull,
      );
    });
  });

  group('fieldSourceName', () {
    test('no row on a field with a value is the scan\'s own', () {
      expect(fieldSourceName(l10n, source: null, hasValue: true), 'tags');
    });

    test('no row on an empty field has nothing to attribute', () {
      expect(fieldSourceName(l10n, source: null, hasValue: false), isNull);
    });

    test('an episode with no row reads as the feed', () {
      expect(
        fieldSourceName(l10n, source: null, hasValue: true, fromFeed: true),
        'the feed',
      );
    });

    test('a row names its producer, and the provider wins over the source', () {
      expect(fieldSourceName(l10n, source: 'user', hasValue: true), 'you');
      expect(
        fieldSourceName(
          l10n,
          source: 'enrichment',
          provider: 'musicbrainz',
          hasValue: true,
        ),
        'MusicBrainz',
      );
    });

    test('a row stands even when the field holds no value', () {
      expect(fieldSourceName(l10n, source: 'user', hasValue: false), 'you');
    });
  });
}
