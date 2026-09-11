import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';
import '../theme/ember_theme.dart';
import 'scrubbable_field.dart';

/// Compact Vector3 field with scrubbable X, Y, and Z inputs.
class Vector3Field extends StatelessWidget {
  final String? label;
  final Vector3 value;
  final ValueChanged<Vector3> onChanged;
  final double step;
  final double? min;
  final double? max;

  const Vector3Field({
    super.key,
    this.label,
    required this.value,
    required this.onChanged,
    this.step = 0.1,
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
                onChanged: (val) => onChanged(Vector3(val, value.y, value.z)),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: ScrubbableField(
                label: 'Y',
                value: value.y,
                step: step,
                min: min,
                max: max,
                labelColor: EmberTheme.accentGreen,
                onChanged: (val) => onChanged(Vector3(value.x, val, value.z)),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: ScrubbableField(
                label: 'Z',
                value: value.z,
                step: step,
                min: min,
                max: max,
                labelColor: EmberTheme.accentBlue,
                onChanged: (val) => onChanged(Vector3(value.x, value.y, val)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
