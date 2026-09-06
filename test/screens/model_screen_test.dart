import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/screens/model_screen.dart';
import 'package:kouyu/theme.dart';
import 'package:kouyu/translation/model_asset.dart';
import 'package:kouyu/translation/model_store.dart';

/// A store the test drives directly, so the screen can be shown in every state
/// without a 533MB download.
class _FakeStore implements ModelStore {
  _FakeStore(ModelState state) : status = ValueNotifier(ModelStatus(state));

  @override
  final ModelAsset asset = ModelAsset.qwen08b;

  @override
  final ValueNotifier<ModelStatus> status;

  int downloads = 0;
  int cancels = 0;
  int removals = 0;
  bool? enabledTo;

  @override
  Future<void> download() async => downloads++;

  @override
  void cancel() => cancels++;

  @override
  Future<void> remove() async => removals++;

  @override
  Future<void> setEnabled(bool enabled) async => enabledTo = enabled;

  @override
  void dispose() => status.dispose();
}

void main() {
  Future<_FakeStore> show(
    WidgetTester tester,
    ModelState state, {
    Size size = const Size(375, 812),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final store = _FakeStore(state);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: kLightTheme,
        home: ModelScreen(store: store),
      ),
    );
    return store;
  }

  String status(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('model-status'))).data!;

  testWidgets('offers the download when there is none', (tester) async {
    final store = await show(tester, ModelState.absent);
    expect(status(tester), contains('533 MB'));
    await tester.tap(find.byKey(const Key('model-download')));
    expect(store.downloads, 1);
  });

  // A learner who lost the connection should not be asked for 533MB again.
  testWidgets('offers to resume rather than restart', (tester) async {
    final store = await show(tester, ModelState.failed);
    store.status.value = const ModelStatus(
      ModelState.failed,
      received: 200000000,
      total: 532517120,
      error: 'No connection to the model host.',
    );
    await tester.pump();

    expect(status(tester), 'No connection to the model host.');
    expect(find.text('Resume download'), findsOneWidget);
  });

  testWidgets('shows progress while downloading, and can be stopped', (
    tester,
  ) async {
    final store = await show(tester, ModelState.downloading);
    store.status.value = const ModelStatus(
      ModelState.downloading,
      received: 133129280,
      total: 532517120,
    );
    await tester.pump();

    expect(status(tester), contains('133 MB of 533 MB'));
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.25, 0.01));

    await tester.tap(find.byKey(const Key('model-cancel')));
    expect(store.cancels, 1);
  });

  // The checksum pass has no fraction to report, so the bar must not sit at
  // 100% pretending to still be moving.
  testWidgets('spins rather than lying while it verifies', (tester) async {
    await show(tester, ModelState.verifying);
    expect(status(tester), contains('Checking'));
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, isNull);
  });

  testWidgets('switches the model off without deleting it', (tester) async {
    final store = await show(tester, ModelState.ready);
    await tester.tap(find.byKey(const Key('model-enabled')));
    expect(store.enabledTo, isFalse);
    expect(store.removals, 0, reason: 'switching off must keep the download');
  });

  testWidgets('asks before deleting the download', (tester) async {
    final store = await show(tester, ModelState.ready);
    await tester.tap(find.byKey(const Key('model-remove')));
    await tester.pumpAndSettle();

    expect(store.removals, 0);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(store.removals, 0, reason: 'declining must not delete');

    await tester.tap(find.byKey(const Key('model-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model-remove-confirm')));
    await tester.pumpAndSettle();
    expect(store.removals, 1);
  });

  // The web build reaches this screen too, and must be told why there is
  // nothing to download rather than shown a button that does nothing.
  testWidgets('explains itself where there is no model', (tester) async {
    await show(tester, ModelState.unsupported);
    expect(status(tester), contains('browser'));
    expect(find.byKey(const Key('model-download')), findsNothing);
    expect(find.byKey(const Key('model-enabled')), findsNothing);
  });

  testWidgets('fits a narrow screen in every state', (tester) async {
    for (final state in ModelState.values) {
      await show(tester, state, size: const Size(375, 667));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: state.name);
    }
  });

  testWidgets('renders in both themes', (tester) async {
    for (final theme in [kLightTheme, kDarkTheme]) {
      final store = _FakeStore(ModelState.ready);
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: ModelScreen(store: store),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
