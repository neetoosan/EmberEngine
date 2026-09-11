import 'package:flutter/material.dart';
import '../theme/ember_theme.dart';

/// Sleek glassmorphism status pill for displaying stats in HUD and Top Bar.
class StatusPill extends StatelessWidget {
  final double fps;
  final double frameTimeMs;
  final String modeName;
  final int entityCount;
  final Color? accentColor;

  const StatusPill({
    super.key,
    required this.fps,
    required this.frameTimeMs,
    required this.modeName,
    required this.entityCount,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? EmberTheme.accentEmber;

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: EmberTheme.surfaceCard.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EmberTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Activity indicator dot
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: fps >= 55 ? EmberTheme.accentGreen : EmberTheme.accentAmber,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),

          // FPS
          Text(
            '${fps.toInt()} FPS',
            style: EmberTheme.codeStyle.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: EmberTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '|',
            style: TextStyle(color: EmberTheme.textMuted.withValues(alpha: 0.5), fontSize: 10),
          ),
          const SizedBox(width: 6),

          // Frame Time
          Text(
            '${frameTimeMs.toStringAsFixed(1)}ms',
            style: EmberTheme.codeStyle.copyWith(
              fontSize: 10,
              color: EmberTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '|',
            style: TextStyle(color: EmberTheme.textMuted.withValues(alpha: 0.5), fontSize: 10),
          ),
          const SizedBox(width: 6),

          // Dimension Mode
          Text(
            modeName,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '|',
            style: TextStyle(color: EmberTheme.textMuted.withValues(alpha: 0.5), fontSize: 10),
          ),
          const SizedBox(width: 6),

          // Entity Count
          Text(
            '$entityCount Ent',
            style: EmberTheme.codeStyle.copyWith(
              fontSize: 10,
              color: EmberTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
