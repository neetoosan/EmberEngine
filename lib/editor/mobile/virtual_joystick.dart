import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/input.dart';
import '../theme/ember_theme.dart';

/// On-Screen Virtual Touch Controls overlay for Mobile Games and Testing.
///
/// Implements mobile game design best practices:
/// - Generous hit areas (> 44x44 points)
/// - Analog virtual joystick on bottom-left
/// - Action buttons (Jump, Fire, Sprint) on bottom-right
/// - Semi-transparent non-intrusive HUD styling
class VirtualJoystickOverlay extends StatefulWidget {
  final bool isVisible;

  const VirtualJoystickOverlay({super.key, required this.isVisible});

  @override
  State<VirtualJoystickOverlay> createState() => _VirtualJoystickOverlayState();
}

class _VirtualJoystickOverlayState extends State<VirtualJoystickOverlay> {
  Offset _joystickThumb = Offset.zero;
  bool _isDragging = false;
  static const double _baseRadius = 50.0;
  static const double _thumbRadius = 22.0;

  void _onPanStart(DragStartDetails details) {
    _isDragging = true;
    _updateThumb(details.localPosition - const Offset(_baseRadius, _baseRadius));
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _updateThumb(details.localPosition - const Offset(_baseRadius, _baseRadius));
  }

  void _onPanEnd(DragEndDetails details) {
    _isDragging = false;
    _joystickThumb = Offset.zero;
    Input.setVirtualJoystick(vm.Vector2.zero());
    setState(() {});
  }

  void _updateThumb(Offset offset) {
    final dist = offset.distance;
    final maxDist = _baseRadius - _thumbRadius;

    if (dist > maxDist) {
      _joystickThumb = Offset(
        (offset.dx / dist) * maxDist,
        (offset.dy / dist) * maxDist,
      );
    } else {
      _joystickThumb = offset;
    }

    final normX = _joystickThumb.dx / maxDist;
    final normY = _joystickThumb.dy / maxDist;
    Input.setVirtualJoystick(vm.Vector2(normX, normY));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Stack(
          children: [
            // 1. Bottom-Left Analog Virtual Joystick
            Positioned(
              left: 24,
              bottom: 24,
              child: GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: Container(
                  width: _baseRadius * 2,
                  height: _baseRadius * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.35),
                    border: Border.all(
                      color: _isDragging ? EmberTheme.accentFlame : Colors.white.withValues(alpha: 0.25),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Transform.translate(
                      offset: _joystickThumb,
                      child: Container(
                        width: _thumbRadius * 2,
                        height: _thumbRadius * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isDragging
                              ? EmberTheme.accentFlame.withValues(alpha: 0.8)
                              : Colors.white.withValues(alpha: 0.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 2. Bottom-Right Action Buttons
            Positioned(
              right: 24,
              bottom: 24,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Sprint Button
                  _buildActionButton(
                    label: 'Sprint',
                    action: 'sprint',
                    color: EmberTheme.accentAmber,
                    icon: Icons.directions_run,
                  ),
                  const SizedBox(width: 12),

                  // Fire Button
                  _buildActionButton(
                    label: 'Fire',
                    action: 'fire',
                    color: EmberTheme.accentRed,
                    icon: Icons.track_changes,
                  ),
                  const SizedBox(width: 12),

                  // Jump Button
                  _buildActionButton(
                    label: 'Jump',
                    action: 'jump',
                    color: EmberTheme.accentEmber,
                    icon: Icons.arrow_upward,
                    size: 54,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required String action,
    required Color color,
    required IconData icon,
    double size = 48.0,
  }) {
    return Listener(
      onPointerDown: (_) => Input.setVirtualAction(action, true),
      onPointerUp: (_) => Input.setVirtualAction(action, false),
      onPointerCancel: (_) => Input.setVirtualAction(action, false),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.3),
          border: Border.all(color: color.withValues(alpha: 0.8), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
            ),
          ],
        ),
        child: Center(
          child: Icon(icon, size: size * 0.45, color: Colors.white),
        ),
      ),
    );
  }
}
