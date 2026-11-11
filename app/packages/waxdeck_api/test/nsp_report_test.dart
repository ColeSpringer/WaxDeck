import 'package:test/test.dart';
import 'package:waxdeck_api/src/gen/codec.g.dart';
import 'package:waxdeck_api/src/wire.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

const _ctx = WireContext(baseUrl: '');

/// The report's direction and gap kind are the strings the wire spells, not
/// Dart enums: three of their eleven values (`export`, `import`, `operator`)
/// are Dart keywords. Every value is decoded and read back as it came.
void main() {
  group('the NSP report', () {
    test('every direction is kept as the wire spells it', () {
      for (final wire in <String>['export', 'import']) {
        final report = decodeNspReport(<String, Object?>{
          'direction': wire,
        }, _ctx);
        expect(report.direction, wire, reason: wire);
      }
    });

    test('every gap kind is kept as the wire spells it', () {
      for (final wire in <String>[
        'field',
        'operator',
        'value',
        'shape',
        'sort',
        'limit',
        'entity',
        'malformed',
      ]) {
        final report = decodeNspReport(<String, Object?>{
          'direction': 'export',
          'gaps': <Object?>[
            <String, Object?>{
              'kind': wire,
              'code': 'unsupported_field',
              'path': '/root/nodes/0',
              'reason': 'nsp: something',
            },
          ],
        }, _ctx);
        expect(report.gaps.single.kind, wire, reason: wire);
      }
    });

    test('a gap carries its code, its optional halves, and its value', () {
      final mapped = decodeNspReport(<String, Object?>{
        'direction': 'export',
        'gaps': <Object?>[
          <String, Object?>{
            'kind': 'value',
            'code': 'rating_not_whole_star',
            'field': 'rating',
            'op': 'gt',
            'value': 85,
            'path': '/root/nodes/0',
            'reason': 'nsp: rating 85 is not a whole number of stars',
          },
          <String, Object?>{
            'kind': 'limit',
            'code': 'limit_budget',
            'value': 60,
            'mode': 'minutes',
            'path': '/limit',
            'reason': 'nsp: limit 60 is a minutes budget',
          },
        ],
        'notes': <Object?>[
          <String, Object?>{
            'kind': 'shape',
            'code': 'unsupported_key',
            'key': 'limitPercent',
            'path': '/limitPercent',
            'reason': 'nsp: unsupported top-level key: limitPercent',
          },
        ],
      }, _ctx);
      final gap = mapped.gaps.first;
      expect(gap.code, 'rating_not_whole_star');
      expect(gap.field, 'rating');
      expect(gap.op, 'gt');
      expect(gap.value, 85);
      expect(gap.path, '/root/nodes/0');
      expect(mapped.gaps.last.mode, 'minutes');
      expect(mapped.notes.single.key, 'limitPercent');
      // Both lists reach the caller: the dialog renders their union, so
      // a note dropped here is a loss nobody is told about.
      expect(mapped.all, hasLength(3));
      expect(mapped.isLossless, isFalse);
    });

    test('a lossless report is empty on both lists', () {
      final mapped = decodeNspReport(<String, Object?>{
        'direction': 'export',
      }, _ctx);
      expect(mapped.isLossless, isTrue);
      expect(mapped.all, isEmpty);
      expect(mapped.ruleHash, isNull);
      expect(mapped.rule, isNull);
    });

    test('an export report carries its rule hash and the kept rule', () {
      final mapped = decodeNspReport(<String, Object?>{
        'direction': 'export',
        'ruleHash': '0123456789abcdef',
        'gaps': <Object?>[
          <String, Object?>{
            'kind': 'field',
            'code': 'unsupported_field',
            'field': 'mediaType',
            'path': '/root/nodes/1',
            'reason': 'nsp: unsupported field: mediaType',
          },
        ],
        'rule': <String, Object?>{
          'root': <String, Object?>{
            'type': 'all',
            'nodes': <Object?>[
              <String, Object?>{
                'type': 'condition',
                'field': 'genre',
                'op': 'is',
                'value': 'Rock',
              },
            ],
          },
          'sorts': <Object?>[
            <String, Object?>{'field': 'playCount', 'desc': true},
          ],
        },
      }, _ctx);
      expect(mapped.ruleHash, '0123456789abcdef');
      final kept = mapped.rule!;
      expect(kept.root.nodes.single.field, 'genre');
      expect(kept.root.nodes.single.value, 'Rock');
      expect(kept.sorts.single.field, 'playCount');
      expect(kept.sorts.single.desc, isTrue);
    });
  });
}
