import 'package:flutter/material.dart';

/// Minimalist Dark Monochromatic design system for Ember Engine.
///
/// Follows "Minimal Surface, Maximum Control" guidelines:
/// - Surface 0 (Viewport canvas): #121316
/// - Surface 1 (Side panels / drawers): #18191E
/// - Surface 2 (Inputs, cards, search bars): #22242B
/// - Border / divider: #2C2E38
/// - Accent 2D (Flame Teal): #00F5D4
/// - Accent 3D (Ember Indigo): #6366F1
class EmberTheme {
  // Surface Colors
  static const Color surfaceCanvas = Color(0xFF121316);
  static const Color surfacePanel = Color(0xFF18191E);
  static const Color surfaceCard = Color(0xFF22242B);
  static const Color surfaceHover = Color(0xFF2A2D36);
  static const Color surfaceActive = Color(0xFF333642);

  // Border & Dividers
  static const Color borderSubtle = Color(0xFF252730);
  static const Color borderMedium = Color(0xFF2C2E38);
  static const Color borderHighlight = Color(0xFF3D4150);

  // Accent Colors
  static const Color accentFlame = Color(0xFF00F5D4); // 2D Flame Teal
  static const Color accentEmber = Color(0xFF6366F1); // 3D Ember Indigo
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color accentGreen = Color(0xFF22C55E);
  static const Color accentRed = Color(0xFFEF4444);
  static const Color accentBlue = Color(0xFF3B82F6);

  // Text Colors
  static const Color textPrimary = Color(0xFFE2E8F0);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textDark = Color(0xFF121316);

  // Convenience Aliases for Workstation & Launcher
  static const Color panelBg = surfacePanel;
  static const Color canvasBg = surfaceCanvas;
  static const Color surfaceBg = surfaceCard;
  static const Color borderMuted = borderMedium;
  static const Color emberOrange = accentAmber;

  // Typography Styles
  static const TextStyle codeStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 11,
    color: textPrimary,
  );

  static const TextStyle headerStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    color: textSecondary,
  );

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: surfaceCanvas,
      primaryColor: accentEmber,
      canvasColor: surfacePanel,
      cardColor: surfaceCard,
      dividerColor: borderMedium,
      colorScheme: const ColorScheme.dark(
        surface: surfacePanel,
        primary: accentEmber,
        secondary: accentFlame,
        error: accentRed,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(borderHighlight),
        thickness: WidgetStateProperty.all(4),
        radius: const Radius.circular(2),
      ),
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceCard,
          borderRadius: BorderRadius.all(Radius.circular(4)),
          border: Border.fromBorderSide(BorderSide(color: borderMedium)),
        ),
        textStyle: TextStyle(color: textPrimary, fontSize: 11),
      ),
    );
  }
}
