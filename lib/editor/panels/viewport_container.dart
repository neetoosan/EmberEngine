import 'package:flutter/material.dart';
import '../../core/engine_loop.dart';
import '../../core/event_bus.dart';
import '../../subsystems/three_d/viewport3d.dart';
import '../../subsystems/two_d/flame_viewport.dart';

/// Central Adaptive Viewport Canvas.
///
/// Seamlessly swaps between Flame's 2D game canvas and the high-throughput 3D viewport
/// based on [engine.mode].
class ViewportContainer extends StatelessWidget {
  final EmberEngine engine;

  const ViewportContainer({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    final is2D = engine.mode == EngineMode.twoD;

    return Container(
      color: const Color(0xFF121316),
      child: is2D
          ? FlameViewportWidget(engine: engine)
          : Viewport3DWidget(engine: engine),
    );
  }
}
