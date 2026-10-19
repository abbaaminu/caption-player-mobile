import 'package:flutter/material.dart';
import 'screens/player_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PremiumLiveCaptionApp());
}

class PremiumLiveCaptionApp extends StatelessWidget {
  const PremiumLiveCaptionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Premium Live Caption Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.amber,
        useMaterial3: true,
      ),
      home: const PlayerScreen(),
    );
  }
}