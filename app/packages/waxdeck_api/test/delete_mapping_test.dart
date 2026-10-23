import 'package:built_collection/built_collection.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;
import 'package:waxdeck_api/src/mapping.dart';

void main() {
  test('an applied delete carries its totals and what stayed', () {
    final result = deleteItemsResultFromGen(
      gen.DeleteItemsResult(
        (b) => b
          ..applied = true
          ..mode = 'trash'
          ..trashed = 1
          ..deleted = 0
          ..failed = 1
          ..dirsPruned = 2
          ..reclaimedBytes = 0
          ..entries = ListBuilder<gen.DeletePlanEntry>([
            gen.DeletePlanEntry(
              (e) => e
                ..pid = 'tr-1'
                ..files = 1
                ..bytes = 10
                ..paths = ListBuilder<String>(['Shelf/one.flac'])
                ..fileList = ListBuilder<gen.DeletePlanFile>([
                  gen.DeletePlanFile(
                    (f) => f
                      ..filePid = 'fl-1'
                      ..name = 'one.flac'
                      ..role = 'primary',
                  ),
                ]),
            ),
            gen.DeletePlanEntry(
              (e) => e
                ..pid = 'tr-2'
                ..files = 0
                ..bytes = 0
                ..failed = 1
                ..error = 'permission denied'
                ..itemSurvives = true,
            ),
          ]),
      ),
    );
    expect(result.trashed, 1);
    expect(result.failed, 1);
    expect(result.dirsPruned, 2);
    expect(result.entries.first.paths, ['Shelf/one.flac']);
    expect(result.entries.last.failed, 1);
    expect(result.entries.last.error, 'permission denied');
  });

  test('a plan carries no totals', () {
    final plan = deleteItemsResultFromGen(
      gen.DeleteItemsResult(
        (b) => b
          ..applied = false
          ..mode = 'trash'
          ..entries = ListBuilder<gen.DeletePlanEntry>(),
      ),
    );
    expect(plan.trashed, 0);
    expect(plan.failed, 0);
    expect(plan.reclaimedBytes, 0);
  });

  test('a tool task names what it works on', () {
    final task = toolTaskFromGen(
      gen.ToolTask(
        (b) => b
          ..id = 'tk-1'
          ..type = 'book-merge'
          ..state = 'queued'
          ..itemPid = 'bk-1'
          ..itemTitle = 'The Fixture Book'
          ..createdAt = DateTime.utc(2026),
      ),
    );
    expect(task.itemTitle, 'The Fixture Book');
  });
}
