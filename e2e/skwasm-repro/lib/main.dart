import 'dart:math';

import 'package:flutter/material.dart';

// Standalone reproduction for the WaxDeck e2e renderer hang: the wasm
// build trapped with "memory access out of bounds" inside skwasm's
// malloc, on the paragraph-layout path (ParagraphImpl::layout →
// TArray<Block> → sk_malloc), after which the UI thread and the skwasm
// render worker both spun forever on the allocator lock.
//
// This app recreates the two-sided allocator pressure with no WaxDeck
// code at all: every frame the UI thread lays out dozens of fresh
// multi-span paragraphs (each span its own style block) while the
// render worker rasterizes the previous frame's text-heavy picture.
// Query knobs: ?paragraphs=N&spans=M&images=1 — images adds a strip of
// network images whose URLs alternate between 404s and tiny PNGs,
// mirroring the failed cover-art burst that preceded the trap in the
// captured trace.
void main() => runApp(const ReproApp());

final int kParagraphs =
    int.tryParse(Uri.base.queryParameters['paragraphs'] ?? '') ?? 48;
final int kSpans = int.tryParse(Uri.base.queryParameters['spans'] ?? '') ?? 12;
final bool kImages = Uri.base.queryParameters['images'] == '1';

class ReproApp extends StatefulWidget {
  const ReproApp({super.key});

  @override
  State<ReproApp> createState() => _ReproAppState();
}

class _ReproAppState extends State<ReproApp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat();
  final Random _rand = Random(42);
  int _frame = 0;

  static const List<String> _words = [
    'resume', 'chapter', 'device', 'album', 'queue', 'shelf', 'needle',
    'groove', 'sleeve', 'liner', 'vinyl', 'deck', 'wax', 'fade', 'tempo',
    'verse',
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AnimatedBuilder(
        animation: _spin,
        builder: (context, _) {
          _frame++;
          final paragraphs = List<Widget>.generate(kParagraphs, (i) {
            final spans = List<TextSpan>.generate(kSpans, (j) {
              final word = _words[_rand.nextInt(_words.length)];
              return TextSpan(
                text: '$word${_frame % 97} ',
                style: TextStyle(
                  fontSize: 10.0 + ((_frame + i + j) % 13),
                  fontWeight: FontWeight
                      .values[(i + j + _frame) % FontWeight.values.length],
                  fontStyle:
                      (i + j) % 3 == 0 ? FontStyle.italic : FontStyle.normal,
                  letterSpacing: (_frame % 5) * 0.2,
                  color: Color(0xFF000000 | _rand.nextInt(0xFFFFFF)),
                ),
              );
            });
            return Text.rich(
              TextSpan(children: spans),
              textScaler: TextScaler.linear(0.9 + (_frame % 7) * 0.05),
            );
          });
          final images = kImages
              ? List<Widget>.generate(8, (i) {
                  // Half of these 404 on the repro server; the codec
                  // error path frees decode buffers on the shared heap.
                  final n = (_frame ~/ 30) * 8 + i;
                  return Image.network(
                    '/art/$n.png',
                    width: 48,
                    height: 48,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) =>
                        const SizedBox(width: 48, height: 48),
                  );
                })
              : const <Widget>[];
          return Scaffold(
            body: Transform.rotate(
              angle: _spin.value * 2 * pi,
              child: Column(
                children: [
                  if (kImages) Row(children: images),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Wrap(children: paragraphs),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
