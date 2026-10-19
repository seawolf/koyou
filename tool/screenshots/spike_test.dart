import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/theme.dart';

void main() {
  testWidgets('spike', (tester) async {
    final root = Platform.environment['FLUTTER_ROOT'];
    final fonts = '$root/bin/cache/artifacts/material_fonts';
    await tester.runAsync(() async {
      final roboto = FontLoader('Roboto');
      for (final w in ['Regular', 'Medium', 'Bold']) {
        roboto.addFont(
          Future.value(
            ByteData.sublistView(
              File('$fonts/Roboto-$w.ttf').readAsBytesSync(),
            ),
          ),
        );
      }
      await roboto.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('$fonts/MaterialIcons-Regular.otf').readAsBytesSync(),
            ),
          ),
        );
      await icons.load();
    });
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    const key = Key('shot');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: kLightTheme,
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Kǒuyǔ'),
              actions: const [Icon(Icons.star_border), Icon(Icons.translate)],
            ),
            body: const Center(
              child: Text(
                'nǐ hǎo shìjiè · wǒ ài nǐ · lǜ',
                style: TextStyle(fontSize: 28),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        '/private/tmp/claude-501/-Users-seawolf-Code-Kouyu/ded5f48e-ad66-4cc2-a3f4-3980d4a5e635/scratchpad/shots/spike.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
    });
    addTearDown(tester.view.reset);
  });
}
