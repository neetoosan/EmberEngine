import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';
import '../theme/ember_theme.dart';
import 'scrubbable_field.dart';

/// Compact Vector2 field with scrubbable X and Y inputs.
class Vector2Field extends StatelessWidget {
  final String? label;
  final Vector2 value;
  final ValueChanged<Vector2> onChanged;
  final double step;
  final double? min;
  final double? max;

  const Vector2Field({
    super.key,
    this.label,
    required this.value,
    required this.onChanged,
    this.step = 1.0,
    this.min,
    this.max,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: EmberTheme.headerStyle),
          const SizedBox(height: 4),
        ],
        Row(
          children: [
            Expanded(
              child: ScrubbableField(
                label: 'X',
                value: value.x,
                step: step,
                min: min,
                max: max,
                labelColor: EmberTheme.accentRed,
                onChanged: (val) => onChanged(Vector2(val, value.y)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ScrubbableField(
                label: 'Y',
                value: value.y,
                step: step,
                min: min,
                max: max,
                labelColor: EmberTheme.accentGreen,
                onChanged: (val) => onChanged(Vector2(value.x, val)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
