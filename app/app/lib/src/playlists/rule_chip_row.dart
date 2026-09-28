import 'package:waxdeck_ui/waxdeck_ui.dart';

/// A rule's chips (from `describeRule`) as one wrapping row, the way the
/// detail header draws them.
class RuleChipRow extends StatelessWidget {
  const RuleChipRow(this.chips, {super.key, this.trailing = const <Widget>[]});

  final List<String> chips;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: WaxSpace.s8,
    runSpacing: WaxSpace.s8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: <Widget>[for (final chip in chips) CodecChip(chip), ...trailing],
  );
}
