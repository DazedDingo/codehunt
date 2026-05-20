import 'package:flutter/material.dart';

import 'screens/home.dart';

void main() {
  runApp(const CodehuntApp());
}

class CodehuntApp extends StatelessWidget {
  const CodehuntApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1A3D3A);
    return MaterialApp(
      title: 'codehunt',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      // Default to dark — codehunt is a "phone in low-light at checkout" app
      // and the user prefers dark across the board.
      themeMode: ThemeMode.dark,
      home: const HomeScreen(),
    );
  }
}
