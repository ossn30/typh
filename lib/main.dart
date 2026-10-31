import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Dark status bar and navigation bar styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF090909),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const Glyph3aApp());
}

class Glyph3aApp extends StatelessWidget {
  const Glyph3aApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nothing Glyph 3a',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090909),
        primaryColor: const Color(0xFFE10600), // Nothing Red
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE10600),
          secondary: Colors.white,
          surface: Color(0xFF141414),
          onPrimary: Colors.white,
          onSurface: Colors.white,
        ),
        fontFamily: 'Roboto',
        useMaterial3: false,
      ),
      home: const HomeScreen(),
    );
  }
}
