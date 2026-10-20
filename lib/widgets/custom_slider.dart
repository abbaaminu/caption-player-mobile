import 'package:flutter/material.dart';

class CustomSlider extends StatelessWidget {
  const CustomSlider({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.enabled = true,
    this.semanticFormatterCallback,
  });

  final double value;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final bool enabled;
  final String Function(double)? semanticFormatterCallback;

  @override
  Widget build(BuildContext context) {
    final safeMax = max.isFinite && max > 0 ? max : 1.0;
    final safeValue = value.isFinite
        ? value.clamp(0.0, safeMax).toDouble()
        : 0.0;

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        disabledActiveTrackColor: Colors.white24,
        disabledInactiveTrackColor: Colors.white12,
        disabledThumbColor: Colors.white38,
      ),
      child: Slider(
        value: safeValue,
        min: 0,
        max: safeMax,
        onChanged: enabled ? onChanged : null,
        onChangeEnd: enabled ? onChangeEnd : null,
        semanticFormatterCallback: semanticFormatterCallback,
      ),
    );
  }
}
