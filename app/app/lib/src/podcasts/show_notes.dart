import 'package:waxdeck_ui/waxdeck_ui.dart';
import '../shell/semantics_ids.dart';

/// Renders the server's sanitized show-notes HTML.
///
/// A deliberately small hand-rolled renderer for the server sanitizer's
/// allowlist only (paragraphs, headings, lists, emphasis, links, code,
/// blockquote, hr). It never executes anything: input is parsed with a
/// tolerant tag scanner into plain text spans, so unknown or malformed
/// markup degrades to its text content instead of crashing. Images are
/// skipped; tables flatten to text.
class ShowNotesView extends StatelessWidget {
  const ShowNotesView({super.key, required this.html, this.onOpenLink});

  final String html;

  /// Invoked with the href when a link is tapped; callers pass the
  /// UrlOpenerPort's open. Links render inert when null.
  final void Function(String url)? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final blocks = parseShowNotes(html);
    if (blocks.isEmpty) return const SizedBox.shrink();
    var linkIndex = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: WaxSpace.s8),
            child: _blockWidget(context, block, () => linkIndex++),
          ),
      ],
    );
  }

  Widget _blockWidget(
    BuildContext context,
    ShowNotesBlock block,
    int Function() nextLinkIndex,
  ) {
    final theme = Theme.of(context);
    final colors = WaxColors.of(context);
    // The notes' own heading ramp, mapped onto the type scale: three
    // sizes and then a floor, because HTML nests six levels and a
    // reader can tell three apart.
    final baseStyle = switch (block.kind) {
      ShowNotesBlockKind.heading1 => WaxType.headline,
      ShowNotesBlockKind.heading2 => WaxType.titleEntity,
      ShowNotesBlockKind.heading3 => WaxType.titleItem,
      ShowNotesBlockKind.heading4 ||
      ShowNotesBlockKind.heading5 ||
      ShowNotesBlockKind.heading6 => WaxType.label,
      _ => WaxType.body,
    }.copyWith(color: colors.textPrimary);
    switch (block.kind) {
      case ShowNotesBlockKind.rule:
        return const Divider();
      case ShowNotesBlockKind.pre:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(WaxSpace.s8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: WaxRadius.chip,
          ),
          child: Text(
            block.runs.map((r) => r.text).join(),
            style: WaxType.monoData.copyWith(color: colors.textPrimary),
          ),
        );
      case ShowNotesBlockKind.listItem:
        return Padding(
          padding: const EdgeInsets.only(left: WaxSpace.s16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${block.marker ?? '-'} ', style: baseStyle),
              Expanded(
                child: _richText(context, block, baseStyle, nextLinkIndex),
              ),
            ],
          ),
        );
      case ShowNotesBlockKind.blockquote:
        return Container(
          padding: const EdgeInsets.only(left: WaxSpace.s12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.outlineVariant,
                width: 3,
              ),
            ),
          ),
          child: _richText(
            context,
            block,
            baseStyle.copyWith(color: colors.textSecondary),
            nextLinkIndex,
          ),
        );
      default:
        return _richText(context, block, baseStyle, nextLinkIndex);
    }
  }

  Widget _richText(
    BuildContext context,
    ShowNotesBlock block,
    TextStyle baseStyle,
    int Function() nextLinkIndex,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          for (final run in block.runs)
            _runSpan(colorScheme, baseStyle, run, nextLinkIndex),
        ],
      ),
    );
  }

  InlineSpan _runSpan(
    ColorScheme colorScheme,
    TextStyle baseStyle,
    ShowNotesRun run,
    int Function() nextLinkIndex,
  ) {
    final decorations = <TextDecoration>[
      if (run.underline || run.href != null) TextDecoration.underline,
      if (run.strike) TextDecoration.lineThrough,
    ];
    final style = TextStyle(
      fontWeight: run.bold ? FontWeight.bold : null,
      fontStyle: run.italic ? FontStyle.italic : null,
      fontFamily: run.code ? 'monospace' : null,
      decoration: decorations.isEmpty
          ? null
          : TextDecoration.combine(decorations),
      color: run.href == null ? null : colorScheme.primary,
    );
    final href = run.href;
    if (href == null) {
      return TextSpan(text: run.text, style: style);
    }
    final index = nextLinkIndex();
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Semantics(
        identifier: SemanticsIds.notesLink(index),
        link: true,
        label: run.text,
        child: GestureDetector(
          onTap: onOpenLink == null ? null : () => onOpenLink!(href),
          child: Text(run.text, style: baseStyle.merge(style)),
        ),
      ),
    );
  }
}

/// Block kinds the mini renderer distinguishes.
enum ShowNotesBlockKind {
  paragraph,
  heading1,
  heading2,
  heading3,
  heading4,
  heading5,
  heading6,
  listItem,
  blockquote,
  pre,
  rule,
}

/// One styled run of text inside a block.
class ShowNotesRun {
  const ShowNotesRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.code = false,
    this.href,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool code;
  final String? href;
}

/// One rendered block: a paragraph, heading, list item, quote, code
/// block, or rule.
class ShowNotesBlock {
  const ShowNotesBlock(this.kind, this.runs, {this.marker});

  final ShowNotesBlockKind kind;
  final List<ShowNotesRun> runs;

  /// List-item marker text ('-' or '3.').
  final String? marker;
}

/// Parses sanitized HTML into renderable blocks. Exposed for unit tests.
List<ShowNotesBlock> parseShowNotes(String html) => _Parser(html).parse();

class _ListContext {
  _ListContext(this.ordered);
  final bool ordered;
  int counter = 0;
}

class _Parser {
  _Parser(this.source);

  final String source;
  final blocks = <ShowNotesBlock>[];
  final runs = <ShowNotesRun>[];

  var bold = 0;
  var italic = 0;
  var underline = 0;
  var strike = 0;
  var code = 0;
  var pre = false;
  var dropped = 0;
  var quote = 0;
  final hrefs = <String>[];
  final lists = <_ListContext>[];
  var kind = ShowNotesBlockKind.paragraph;
  String? marker;

  List<ShowNotesBlock> parse() {
    var i = 0;
    while (i < source.length) {
      final lt = source.indexOf('<', i);
      if (lt < 0) {
        _text(source.substring(i));
        break;
      }
      if (lt > i) _text(source.substring(i, lt));
      // Comments and doctypes: skip to their closing marker so their
      // innards never render as text.
      if (source.startsWith('<!--', lt)) {
        final end = source.indexOf('-->', lt);
        i = end < 0 ? source.length : end + 3;
        continue;
      }
      final gt = source.indexOf('>', lt);
      if (gt < 0) {
        // A dangling '<' at the end: tolerate it as literal text.
        _text(source.substring(lt));
        break;
      }
      _tag(source.substring(lt + 1, gt).trim());
      i = gt + 1;
    }
    _flushBlock();
    return blocks;
  }

  void _tag(String raw) {
    if (raw.isEmpty || raw.startsWith('!') || raw.startsWith('?')) return;
    final closing = raw.startsWith('/');
    final body = closing ? raw.substring(1) : raw;
    final match = RegExp(r'^[a-zA-Z][a-zA-Z0-9]*').firstMatch(body);
    if (match == null) {
      // Not a tag at all ("< 3"): keep it as literal text.
      _text('<$raw>');
      return;
    }
    final name = match[0]!.toLowerCase();
    switch (name) {
      case 'br':
        _text('\n', literal: true);
      case 'hr':
        _flushBlock();
        blocks.add(const ShowNotesBlock(ShowNotesBlockKind.rule, []));
      case 'p' || 'div' || 'table' || 'thead' || 'tbody' || 'tfoot':
        _flushBlock();
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        _flushBlock();
        if (!closing) {
          kind = switch (name) {
            'h1' => ShowNotesBlockKind.heading1,
            'h2' => ShowNotesBlockKind.heading2,
            'h3' => ShowNotesBlockKind.heading3,
            'h4' => ShowNotesBlockKind.heading4,
            'h5' => ShowNotesBlockKind.heading5,
            _ => ShowNotesBlockKind.heading6,
          };
        }
      case 'ul' || 'ol':
        _flushBlock();
        if (closing) {
          if (lists.isNotEmpty) lists.removeLast();
        } else {
          lists.add(_ListContext(name == 'ol'));
        }
      case 'li':
        _flushBlock();
        if (!closing) {
          kind = ShowNotesBlockKind.listItem;
          final list = lists.isEmpty ? null : lists.last;
          marker = (list?.ordered ?? false) ? '${++list!.counter}.' : '-';
        }
      case 'blockquote':
        _flushBlock();
        quote += closing ? -1 : 1;
        if (quote < 0) quote = 0;
      case 'pre':
        _flushBlock();
        pre = !closing;
        if (!closing) kind = ShowNotesBlockKind.pre;
      case 'b' || 'strong':
        bold += closing ? -1 : 1;
      case 'i' || 'em':
        italic += closing ? -1 : 1;
      case 'u':
        underline += closing ? -1 : 1;
      case 's' || 'del' || 'strike':
        strike += closing ? -1 : 1;
      case 'code':
        code += closing ? -1 : 1;
      case 'a':
        if (closing) {
          if (hrefs.isNotEmpty) hrefs.removeLast();
        } else {
          final href = RegExp(
            'href\\s*=\\s*("([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
            caseSensitive: false,
          ).firstMatch(raw);
          hrefs.add(href?[2] ?? href?[3] ?? href?[4] ?? '');
        }
      case 'img':
        // Images are out of scope: render nothing.
        break;
      case 'script' || 'style':
        // Sanitized input never carries these, but the renderer must
        // shrug them off: their content is dropped, never rendered.
        dropped += closing ? -1 : 1;
        if (dropped < 0) dropped = 0;
      case 'tr':
        _text('\n', literal: true);
      case 'td' || 'th':
        if (closing) _text(' ', literal: true);
      default:
        // Unknown tags render their text content: ignore the tag itself.
        break;
    }
  }

  void _text(String raw, {bool literal = false}) {
    if (dropped > 0) return;
    var text = literal ? raw : _decodeEntities(raw);
    if (!pre && !literal) {
      text = text.replaceAll(RegExp(r'[ \t\r\n]+'), ' ');
    }
    if (text.isEmpty) return;
    final href = hrefs.isEmpty || hrefs.last.isEmpty ? null : hrefs.last;
    runs.add(
      ShowNotesRun(
        text,
        bold: bold > 0,
        italic: italic > 0,
        underline: underline > 0,
        strike: strike > 0,
        code: code > 0,
        href: href,
      ),
    );
  }

  void _flushBlock() {
    // Trim whitespace-only edges so tag soup does not produce empty
    // paragraphs between real ones.
    while (runs.isNotEmpty && runs.first.text.trim().isEmpty) {
      runs.removeAt(0);
    }
    while (runs.isNotEmpty && runs.last.text.trim().isEmpty) {
      runs.removeLast();
    }
    if (runs.isNotEmpty) {
      final blockKind = quote > 0 && kind == ShowNotesBlockKind.paragraph
          ? ShowNotesBlockKind.blockquote
          : kind;
      blocks.add(ShowNotesBlock(blockKind, List.of(runs), marker: marker));
    }
    runs.clear();
    kind = ShowNotesBlockKind.paragraph;
    marker = null;
  }

  static String _decodeEntities(String s) {
    return s.replaceAllMapped(RegExp(r'&(#[xX]?[0-9a-fA-F]+|[a-zA-Z]+);'), (m) {
      final entity = m[1]!;
      if (entity.startsWith('#')) {
        final hex = entity.length > 1 && (entity[1] == 'x' || entity[1] == 'X');
        final value = int.tryParse(
          entity.substring(hex ? 2 : 1),
          radix: hex ? 16 : 10,
        );
        if (value == null || value < 0 || value > 0x10FFFF) return m[0]!;
        return String.fromCharCode(value);
      }
      return switch (entity) {
        'amp' => '&',
        'lt' => '<',
        'gt' => '>',
        'quot' => '"',
        'apos' => "'",
        'nbsp' => ' ',
        _ => m[0]!,
      };
    });
  }
}
