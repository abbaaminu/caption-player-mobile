import 'package:flutter/material.dart';

/// Accessible, non-interactive live-caption surface shown over the media.
class CaptionOverlay extends StatelessWidget {
  const CaptionOverlay({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Semantics(
          container: true,
          liveRegion: true,
          label: 'Live captions',
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: Text(
                  text,
                  key: ValueKey(text),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFFF00),
                    fontSize: 19,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
