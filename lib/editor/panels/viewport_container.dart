import 'package:flutter/material.dart';
import '../../core/engine_loop.dart';
import '../../core/event_bus.dart';
import '../../core/mouse_lock.dart';
import '../../subsystems/three_d/viewport3d.dart';
import '../../subsystems/two_d/flame_viewport.dart';

/// Central Adaptive Viewport Canvas.
///
/// Seamlessly swaps between Flame's 2D game canvas and the high-throughput 3D viewport
/// based on [engine.mode]. While a running game wants the mouse captured
/// (first-person mouse-look), a click captures it; until then the game waits
/// behind a "Click to play" note.
class ViewportContainer extends StatelessWidget {
  final EmberEngine engine;

  const ViewportContainer({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    final is2D = engine.mode == EngineMode.twoD;

    return Container(
      color: const Color(0xFF121316),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (engine.playState == PlayState.playing && MouseLock.wanted && !MouseLock.locked) MouseLock.lock();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            is2D ? FlameViewportWidget(engine: engine) : Viewport3DWidget(engine: engine),
            ValueListenableBuilder<int>(
              valueListenable: engine.frame,
              builder: (context, _, _) => engine.waitingForMouse ? const _ClickToPlay() : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClickToPlay extends StatelessWidget {
  const _ClickToPlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        color: const Color(0x66000000),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xE6111318),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFF97316), width: 1.5),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mouse_outlined, color: Color(0xFFF97316), size: 26),
              SizedBox(height: 6),
              Text('Click to play', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('The mouse aims. Press Esc to free it.', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
