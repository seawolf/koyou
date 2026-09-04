import 'package:flutter/material.dart';

/// Placeholder home screen.
///
/// It stands in for the real app while the foundations are being laid, and
/// doubles as a smoke test: it proves the app boots, picks up the theme, and
/// renders Hanzi, pinyin diacritics, and Latin text together.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kǒuyǔ'),
        backgroundColor: theme.colorScheme.primaryContainer,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('你好，世界', style: theme.textTheme.displayMedium),
              const SizedBox(height: 12),
              Text(
                'Nǐ hǎo, shìjiè',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Hello, world',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
