import 'package:flutter/material.dart';

import 'screens/home.dart';

void main() {
  runApp(const CodehuntApp());
}

class CodehuntApp extends StatelessWidget {
  const CodehuntApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'codehunt',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A3D3A)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
