import 'package:flutter/material.dart';

import '../translation/model_asset.dart';
import '../translation/model_store.dart';

/// Fetches and manages the on-device translator's weights.
///
/// A screen of its own rather than a dialog: it holds a 533MB download that a
/// learner may want to watch, leave, and come back to.
class ModelScreen extends StatelessWidget {
  const ModelScreen({super.key, required this.store});

  final ModelStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = store.asset;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Whole phrases'),
        backgroundColor: theme.colorScheme.primaryContainer,
      ),
      body: ValueListenableBuilder<ModelStatus>(
        valueListenable: store.status,
        builder: (context, status, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // What it buys, before what it costs. The dictionary already
            // translates words; this is the part that handles grammar.
            Text(
              'The dictionary translates words and set phrases on its own. A '
              'model translates whole sentences — word order, grammar, and '
              'questions.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Text(
              asset.label,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            Text(
              '${asset.sizeLabel} · ${asset.licence} · runs on this device, '
              'offline',
              key: const Key('model-detail'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            _Status(status: status, asset: asset),
            const SizedBox(height: 24),
            ..._actions(context, status),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context, ModelStatus status) {
    switch (status.state) {
      case ModelState.unsupported:
        return const [];
      case ModelState.absent:
      case ModelState.failed:
        return [
          FilledButton.icon(
            key: const Key('model-download'),
            onPressed: store.download,
            icon: const Icon(Icons.download_outlined),
            label: Text(status.received > 0 ? 'Resume download' : 'Download'),
          ),
        ];
      case ModelState.downloading:
      case ModelState.verifying:
        return [
          OutlinedButton.icon(
            key: const Key('model-cancel'),
            // Verifying cannot be interrupted usefully — it is a read of a
            // file already on disk — so the button only stops a download.
            onPressed: status.state == ModelState.downloading
                ? store.cancel
                : null,
            icon: const Icon(Icons.close),
            label: const Text('Stop'),
          ),
        ];
      case ModelState.ready:
      case ModelState.disabled:
        final on = status.state == ModelState.ready;
        return [
          SwitchListTile(
            key: const Key('model-enabled'),
            value: on,
            onChanged: store.setEnabled,
            title: const Text('Translate whole phrases'),
            subtitle: Text(
              on
                  ? 'On. Switching off frees the memory and keeps the download.'
                  : 'Off. The dictionary is answering on its own.',
            ),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('model-remove'),
            onPressed: () => _confirmRemove(context),
            icon: const Icon(Icons.delete_outline),
            label: Text('Delete the ${store.asset.sizeLabel} download'),
          ),
        ];
    }
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete the download?'),
        content: Text(
          'Getting it back means downloading ${store.asset.sizeLabel} again. '
          'To stop using the model without deleting it, switch it off instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            key: const Key('model-remove-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (go ?? false) await store.remove();
  }
}

/// Where the weights have got to, in a sentence.
class _Status extends StatelessWidget {
  const _Status({required this.status, required this.asset});

  final ModelStatus status;
  final ModelAsset asset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = status.progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _sentence,
          key: const Key('model-status'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: status.state == ModelState.failed
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (status.state == ModelState.downloading ||
            status.state == ModelState.verifying) ...[
          const SizedBox(height: 12),
          // Determinate while there is a fraction to show; the checksum pass
          // has no fraction, so it spins rather than sitting at 100%.
          LinearProgressIndicator(value: progress),
        ],
      ],
    );
  }

  String get _sentence => switch (status.state) {
    ModelState.unsupported =>
      'Whole-phrase translation needs an app that can run a model on the '
          'device, so it is not available in a browser. The dictionary works '
          'here as it always has.',
    ModelState.absent =>
      'Not downloaded. Best over Wi-Fi — it is ${asset.sizeLabel}, and it is '
          'kept on the device afterwards.',
    ModelState.downloading =>
      '${_mb(status.received)} of ${_mb(status.total)}. Leaving this screen '
          'does not stop it.',
    ModelState.verifying => 'Checking the download.',
    ModelState.ready => 'Ready, and used for anything longer than one word.',
    ModelState.disabled => 'Downloaded but switched off.',
    ModelState.failed =>
      status.error ??
          'The download did not finish. What arrived has been kept, so it '
              'can carry on from there.',
  };

  static String _mb(int bytes) => '${(bytes / 1000000).round()} MB';
}
