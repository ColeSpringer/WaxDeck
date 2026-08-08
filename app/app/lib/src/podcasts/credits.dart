import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// Renders `<podcast:person>` credits as a titled list of names with their
/// roles. A person carrying an [FeedPerson.href] opens it on tap; a portrait
/// [FeedPerson.img] shows as an avatar, falling back to an initial.
class PodcastCredits extends StatelessWidget {
  const PodcastCredits({
    super.key,
    required this.persons,
    required this.onOpenLink,
  });

  final List<FeedPerson> persons;
  final void Function(String url) onOpenLink;

  @override
  Widget build(BuildContext context) {
    if (persons.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Credits'),
        for (final person in persons)
          Builder(
            builder: (context) {
              final href = person.href;
              // Treat an empty href like an absent one (the server already
              // omits empties; this keeps the widget robust to any source).
              final hasLink = href != null && href.isNotEmpty;
              return WaxOptionRow(
                leading: _Avatar(person: person, colorScheme: colorScheme),
                title: person.name,
                subtitle: person.role == null || person.role!.isEmpty
                    ? null
                    : _titleCase(person.role!),
                trailing: hasLink
                    ? const WaxIcon(WaxIcons.openExternal, size: 16)
                    : null,
                onTap: hasLink ? () => onOpenLink(href) : null,
              );
            },
          ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.person, required this.colorScheme});

  final FeedPerson person;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final img = person.img;
    final hasImg = img != null && img.isNotEmpty;
    final initial = person.name.isEmpty ? '?' : person.name.characters.first;
    return CircleAvatar(
      radius: 16,
      backgroundColor: colorScheme.surfaceContainerHighest,
      // A broken portrait URL falls back to the initial: the image fails to
      // paint over the initial child, and onForegroundImageError swallows the
      // load exception so an untrusted feed's dead URL never spams the logs.
      // (CircleAvatar asserts the error handler is null when there is no
      // foreground image, so both gate on hasImg.)
      foregroundImage: hasImg ? NetworkImage(img) : null,
      onForegroundImageError: hasImg ? (_, _) {} : null,
      child: Text(initial.toUpperCase()),
    );
  }
}

String _titleCase(String role) {
  if (role.isEmpty) return role;
  return role[0].toUpperCase() + role.substring(1);
}
