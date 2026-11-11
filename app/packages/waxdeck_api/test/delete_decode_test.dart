import 'package:test/test.dart';
import 'package:waxdeck_api/src/gen/codec.g.dart';
import 'package:waxdeck_api/src/wire.dart';

const _ctx = WireContext(baseUrl: '');

void main() {
  test('an applied delete carries its totals and what stayed', () {
    final result = decodeDeleteItemsResult({
      'applied': true,
      'mode': 'trash',
      'trashed': 1,
      'deleted': 0,
      'failed': 1,
      'dirsPruned': 2,
      'reclaimedBytes': 0,
      'entries': [
        {
          'pid': 'tr-1',
          'files': 1,
          'bytes': 10,
          'paths': ['Shelf/one.flac'],
          'fileList': [
            {'filePid': 'fl-1', 'name': 'one.flac', 'role': 'primary'},
          ],
        },
        {
          'pid': 'tr-2',
          'files': 0,
          'bytes': 0,
          'failed': 1,
          'error': 'permission denied',
          'itemSurvives': true,
        },
      ],
    }, _ctx);
    expect(result.trashed, 1);
    expect(result.failed, 1);
    expect(result.dirsPruned, 2);
    expect(result.entries.first.paths, ['Shelf/one.flac']);
    expect(result.entries.last.failed, 1);
    expect(result.entries.last.error, 'permission denied');
    // The failed one's item stays; the other's went with its file.
    expect(result.entries.last.itemSurvives, isTrue);
    expect(result.entries.first.itemSurvives, isFalse);
  });

  test('a plan carries no totals', () {
    final plan = decodeDeleteItemsResult({
      'applied': false,
      'mode': 'trash',
      'entries': <Object?>[],
    }, _ctx);
    expect(plan.trashed, 0);
    expect(plan.failed, 0);
    expect(plan.reclaimedBytes, 0);
  });

  test('a tool task names what it works on', () {
    final task = decodeToolTask({
      'id': 'tk-1',
      'type': 'book-merge',
      'state': 'queued',
      'itemPid': 'bk-1',
      'itemTitle': 'The Fixture Book',
      'createdAt': '2026-01-01T00:00:00Z',
    }, _ctx);
    expect(task.itemTitle, 'The Fixture Book');
  });
}
