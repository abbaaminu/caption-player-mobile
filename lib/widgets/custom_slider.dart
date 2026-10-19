import 'package:flutter/material.dart';

class CustomSlider extends StatelessWidget {
  final double value;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const CustomSlider({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      child: Slider(
        value: value.clamp(0.0, max),
        min: 0.0,
        max: max <= 0 ? 1.0 : max,
        activeColor: Colors.amber,
        inactiveColor: Colors.grey,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}