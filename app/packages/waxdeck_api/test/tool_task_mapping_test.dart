import 'package:test/test.dart';
import 'package:waxdeck_api/src/mapping.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;

void main() {
  test('a waiting task carries why it waits, when it tries next, and that '
      'its book is in the trash', () {
    final task = toolTaskFromGen(
      gen.ToolTask(
        (b) => b
          ..id = 'tt-1'
          ..type = 'book-merge'
          ..state = 'running'
          ..itemPid = 'bk-1'
          ..progressPct = 100
          ..error = 'the library folder refused the write: permission denied'
          ..waitReason = 'storage-unwritable'
          ..retryAt = DateTime.utc(2026, 10, 22, 12, 30)
          ..bookInTrash = true
          ..createdAt = DateTime.utc(2026, 10, 22, 12),
      ),
    );

    expect(task.waitReason, 'storage-unwritable');
    expect(task.retryAt, DateTime.utc(2026, 10, 22, 12, 30));
    expect(task.retryAt!.isUtc, isTrue);
    expect(task.bookInTrash, isTrue);
  });

  test('a task at work leaves the waiting fields empty', () {
    final task = toolTaskFromGen(
      gen.ToolTask(
        (b) => b
          ..id = 'tt-2'
          ..type = 'cue-split'
          ..state = 'running'
          ..createdAt = DateTime.utc(2026, 10, 22, 12),
      ),
    );

    expect(task.waitReason, isNull);
    expect(task.retryAt, isNull);
    expect(task.bookInTrash, isFalse);
  });

  test('a parked task is finished, as a done or failed one is', () {
    ToolTask at(String state) => ToolTask(
      id: 'tt-1',
      type: 'book-merge',
      state: state,
      createdAt: DateTime.utc(2026, 10, 22),
    );
    expect(
      [
        for (final state in ['queued', 'running', 'done', 'failed', 'parked'])
          at(state).finished,
      ],
      [false, false, true, true, true],
    );
  });
}
