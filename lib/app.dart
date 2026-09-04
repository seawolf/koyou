import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'theme.dart';

class KouyuApp extends StatelessWidget {
  const KouyuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kǒuyǔ',
      theme: kLightTheme,
      darkTheme: kDarkTheme,
      home: const HomeScreen(),
    );
  }
}
