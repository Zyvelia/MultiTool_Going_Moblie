import 'package:flutter/material.dart';
import 'screens/home_shell.dart';

void main() {
  runApp(const MultiToolRemoteApp());
}

class MultiToolRemoteApp extends StatelessWidget {
  const MultiToolRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Zs Multi Tool Remote",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4EA1FF),
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF151922),
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1B2030),
          elevation: 0,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF151922),
          indicatorColor: Color(0xFF23304a),
        ),
      ),
      home: const HomeShell(),
    );
  }
}
