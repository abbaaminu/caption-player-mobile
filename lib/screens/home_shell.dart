import 'package:flutter/material.dart';

import '../system_caption/system_caption_platform.dart';
import '../theme/app_theme.dart';
import 'player_screen.dart';
import 'system_captions_screen.dart';

/// Top-level navigation.
///
/// On Android there are two tabs: system-wide **Live Caption** (captions for
/// any audio playing on the phone) and the **Player** (open a file and caption
/// it). Other platforms only have the player.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    if (!systemCaptionsAvailableOnThisPlatform) {
      return const PlayerScreen();
    }

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          SystemCaptionsScreen(isActive: _index == 0),
          const PlayerScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppTheme.surfaceRaised,
        indicatorColor: AppTheme.accent.withValues(alpha: 0.22),
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.closed_caption_outlined),
            selectedIcon: Icon(Icons.closed_caption),
            label: 'Live Caption',
          ),
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle),
            label: 'Player',
          ),
        ],
      ),
    );
  }
}
