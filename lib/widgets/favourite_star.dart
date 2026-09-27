import 'package:flutter/material.dart';

import '../favourites/favourites.dart';
import '../pinyin/word.dart';

/// The star in an app bar: filled when the line is kept, outlined when not.
///
/// Shared by the compose and translate screens, so saving behaves the same
/// wherever a line comes from. It shows state rather than only acting,
/// because that is what a star means everywhere else, and it is what stops a
/// line being saved twice.
class FavouriteStar extends StatelessWidget {
  const FavouriteStar({
    super.key,
    required this.favourites,
    required this.line,
    required this.onView,
    this.meaning,
  });

  final Favourites favourites;

  /// The line to keep, or null when there is nothing to keep yet.
  final List<Word>? line;

  /// Kept beside it, as it is showing now.
  final String? meaning;

  /// Opens the list, from the message that follows a save.
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Favourite>>(
      valueListenable: favourites.items,
      builder: (context, _, _) {
        final line = this.line;
        final kept = line == null ? null : favourites.find(line);
        final empty = line == null || Favourite.kept(line).isEmpty;

        return IconButton(
          key: const Key('star'),
          onPressed: empty ? null : () => _toggle(context, line, kept),
          isSelected: kept != null,
          icon: const Icon(Icons.star_border),
          selectedIcon: const Icon(Icons.star),
          tooltip: kept == null
              ? 'Save to favourites'
              : 'Remove from favourites',
        );
      },
    );
  }

  Future<void> _toggle(
    BuildContext context,
    List<Word> line,
    Favourite? kept,
  ) async {
    if (kept != null) {
      // The same question the list asks before a swipe. There is one way to
      // lose a favourite and it always asks first.
      if (await confirmRemoval(context, kept)) await favourites.remove(kept);
      return;
    }
    await favourites.save(line, meaning: meaning);
    if (context.mounted) showSaved(context, onView: onView);
  }
}

/// Asks before a favourite is removed. True if it should go.
///
/// Names the line, so the question can be answered without remembering which
/// row was swiped.
Future<bool> confirmRemoval(BuildContext context, Favourite favourite) async {
  final remove = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        key: const Key('confirm-removal'),
        title: const Text('Remove this favourite?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(favourite.pinyin, style: theme.textTheme.titleLarge),
            if (favourite.meaning case final meaning?)
              Text(
                meaning,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('keep'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            key: const Key('remove'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      );
    },
  );
  return remove ?? false;
}

/// Says a line was kept, and where the list is.
///
/// The action opens the list at once; the text says where it lives for next
/// time. It names the main screen's ⋮ because that is where the list is kept
/// wherever the saving happened.
void showSaved(BuildContext context, {required VoidCallback onView}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const Key('saved'),
        content: const Text(
          'Saved. Your favourites are under ⋮ on the main screen.',
        ),
        action: SnackBarAction(label: 'View', onPressed: onView),
        // A snack bar with an action stays up until it is tapped, by default.
        // This one is a confirmation, not a question, so it goes on its own.
        persist: false,
      ),
    );
}
