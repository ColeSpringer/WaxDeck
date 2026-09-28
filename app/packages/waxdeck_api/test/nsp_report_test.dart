import 'package:test/test.dart';
import 'package:waxdeck_api/src/mapping.dart';
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;

/// The NSP report's two enums are the ones this client is most likely to
/// mistranslate: three of their eleven values (`export`, `import`,
/// `operator`) are Dart keywords, so the generator escapes the Dart name
/// with a trailing underscore while the wire keeps the bare word. A
/// mapper reading `.name` answers a value the contract never defines,
/// and nothing throws - the branch just never matches.
///
/// So every value is deserialized from the wire and asserted back to it.
void main() {
  group('NSP report mapping', () {
    test('every direction survives the round trip to its wire value', () {
      for (final wire in <String>['export', 'import']) {
        final report = gen.standardSerializers.deserializeWith(
          gen.NspReport.serializer,
          <String, Object?>{'direction': wire},
        )!;
        expect(nspReportFromGen(report).direction, wire, reason: wire);
      }
    });

    test('every gap kind survives the round trip to its wire value', () {
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
        final report = gen.standardSerializers.deserializeWith(
          gen.NspReport.serializer,
          <String, Object?>{
            'direction': 'export',
            'gaps': <Object?>[
              <String, Object?>{
                'kind': wire,
                'path': '/root/nodes/0',
                'reason': 'nsp: something',
              },
            ],
          },
        )!;
        expect(nspReportFromGen(report).gaps.single.kind, wire, reason: wire);
      }
    });

    test('a gap carries its optional halves, and the value it held', () {
      final report = gen.standardSerializers.deserializeWith(
        gen.NspReport.serializer,
        <String, Object?>{
          'direction': 'export',
          'gaps': <Object?>[
            <String, Object?>{
              'kind': 'value',
              'field': 'rating',
              'op': 'gt',
              'value': 85,
              'path': '/root/nodes/0',
              'reason': 'nsp: rating 85 is not a whole number of stars',
            },
          ],
          'notes': <Object?>[
            <String, Object?>{
              'kind': 'entity',
              'path': '/entity',
              'reason': 'nsp: tracks only',
            },
          ],
        },
      )!;
      final mapped = nspReportFromGen(report);
      final gap = mapped.gaps.single;
      expect(gap.field, 'rating');
      expect(gap.op, 'gt');
      expect(gap.value, 85);
      expect(gap.path, '/root/nodes/0');
      // Both lists reach the caller: the dialog renders their union, so
      // a note dropped here is a loss nobody is told about.
      expect(mapped.all, hasLength(2));
      expect(mapped.isLossless, isFalse);
    });

    test('a lossless report is empty on both lists', () {
      final report = gen.standardSerializers.deserializeWith(
        gen.NspReport.serializer,
        <String, Object?>{'direction': 'export'},
      )!;
      final mapped = nspReportFromGen(report);
      expect(mapped.isLossless, isTrue);
      expect(mapped.all, isEmpty);
      expect(mapped.ruleHash, isNull);
      expect(mapped.rule, isNull);
    });

    test('an export report carries its rule hash and the kept rule', () {
      final report = gen.standardSerializers.deserializeWith(
        gen.NspReport.serializer,
        <String, Object?>{
          'direction': 'export',
          'ruleHash': '0123456789abcdef',
          'gaps': <Object?>[
            <String, Object?>{
              'kind': 'field',
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
        },
      )!;
      final mapped = nspReportFromGen(report);
      expect(mapped.ruleHash, '0123456789abcdef');
      final kept = mapped.rule!;
      expect(kept.root.nodes.single.field, 'genre');
      expect(kept.root.nodes.single.value, 'Rock');
      expect(kept.sorts.single.field, 'playCount');
      expect(kept.sorts.single.desc, isTrue);
    });
  });
}
