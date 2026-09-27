import 'package:flutter/material.dart';

import '../favourites/favourites.dart';
import '../widgets/favourite_star.dart';

/// The lines the learner kept.
///
/// Pops with the favourite that was tapped, so whoever opened the list decides
/// what opening one means — the compose screen puts it in the input area, and
/// the translate screen hands it on to the compose screen.
class FavouritesScreen extends StatefulWidget {
  const FavouritesScreen({super.key, required this.favourites});

  final Favourites favourites;

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  /// Rows swiped away and confirmed, hidden at once.
  ///
  /// The store removes them a moment later, but a dismissed row still in the
  /// tree on the next frame is an error, so it is not left to the store.
  final Set<Favourite> _gone = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favourites'),
        backgroundColor: theme.colorScheme.primaryContainer,
      ),
      body: ValueListenableBuilder<List<Favourite>>(
        valueListenable: widget.favourites.items,
        builder: (context, items, _) {
          final shown = [
            for (final favourite in items)
              if (!_gone.contains(favourite)) favourite,
          ];

          if (shown.isEmpty) {
            final style = theme.textTheme.bodyLarge?.copyWith(color: muted);
            return Padding(
              padding: const EdgeInsets.all(24),
              // The star drawn as the icon it is, not typed as ☆: no bundled
              // font carries that character, and it rendered as an empty box.
              // The icon font always ships.
              child: Text.rich(
                key: const Key('no-favourites'),
                TextSpan(
                  style: style,
                  children: [
                    const TextSpan(text: 'Nothing saved yet. Tap the '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Icon(
                        Icons.star_border,
                        size: (style?.fontSize ?? 16) * 1.2,
                        color: muted,
                        semanticLabel: 'star',
                      ),
                    ),
                    const TextSpan(text: ' at the top to keep a line here.'),
                  ],
                ),
              ),
            );
          }

          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                // Swiping is not discoverable on its own, so it is said once,
                // above the list rather than beside every row.
                child: Text(
                  'Tap one to open it. Swipe one away to remove it.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
              for (final favourite in shown) _row(context, favourite),
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, Favourite favourite) {
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey(favourite),
      background: _Behind(alignment: Alignment.centerLeft),
      secondaryBackground: _Behind(alignment: Alignment.centerRight),
      confirmDismiss: (_) => confirmRemoval(context, favourite),
      onDismissed: (_) {
        setState(() => _gone.add(favourite));
        widget.favourites.remove(favourite);
      },
      child: ListTile(
        key: ValueKey('favourite-${favourite.pinyin}'),
        title: Text(favourite.pinyin, style: theme.textTheme.titleLarge),
        subtitle: favourite.meaning == null ? null : Text(favourite.meaning!),
        onTap: () => Navigator.of(context).pop(favourite),
      ),
    );
  }
}

/// What shows behind a row as it is swiped.
class _Behind extends StatelessWidget {
  const _Behind({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.errorContainer,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
        ),
      ),
    );
  }
}
