import 'package:flutter/material.dart';
import '../../core/transform2d.dart';
import '../theme/ember_theme.dart';

/// Minimalist, space-saving 3x3 anchor picker designed specifically for 2D / Flame anchors.
class FlameAnchorSelector extends StatelessWidget {
  final EmberAnchor currentAnchor;
  final ValueChanged<EmberAnchor> onSelected;

  const FlameAnchorSelector({
    super.key,
    required this.currentAnchor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: EmberTheme.surfaceCard,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: EmberTheme.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRow([EmberAnchor.topLeft, EmberAnchor.topCenter, EmberAnchor.topRight]),
          const SizedBox(height: 3),
          _buildRow([EmberAnchor.centerLeft, EmberAnchor.center, EmberAnchor.centerRight]),
          const SizedBox(height: 3),
          _buildRow([EmberAnchor.bottomLeft, EmberAnchor.bottomCenter, EmberAnchor.bottomRight]),
        ],
      ),
    );
  }

  Widget _buildRow(List<EmberAnchor> anchors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: anchors.map((anchor) {
        final isSelected = anchor == currentAnchor;
        return Tooltip(
          message: anchor.displayName,
          child: GestureDetector(
            onTap: () => onSelected(anchor),
            child: Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: isSelected ? EmberTheme.accentFlame : EmberTheme.borderHighlight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
