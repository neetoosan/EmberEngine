import 'package:flutter/painting.dart' show Color;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/entity.dart';
import '../core/game_script.dart';
import '../core/scene.dart';
import '../core/transform2d.dart';
import '../subsystems/story/story_player.dart';
import '../subsystems/two_d/camera2d.dart';
import '../subsystems/ui/ui_text.dart';
import '../subsystems/ui/ui_widgets.dart';

/// "The Last Ember": a short visual novel on the Story Player. The story is
/// `the_last_ember.story` (backgrounds, two characters with expressions,
/// three choices, four endings), editable in the Script workspace.
class StoryTemplate {
  static const String art = 'assets/templates/story';
  static const String music = '$art/theme.wav';
  static const String title = 'Title';
  static const String story = 'Story';
  static const String storyFile = 'the_last_ember.story';

  static const List<String> assetFiles = [
    '$art/forge.png', '$art/village.png', '$art/hill.png', '$art/dawn.png', '$art/mira.png', '$art/kai.png', music,
  ];
}

EmberEntity _camera() => EmberEntity(name: 'Camera')
  ..addComponent(Transform2DComponent(position: vm.Vector2(480, 270), size: vm.Vector2.zero()))
  ..addComponent(Camera2DComponent(designWidth: 960, designHeight: 540, backgroundColor: const Color(0xFF0B0B12)));

EmberEntity _text(String name, String text, double size, EmberAnchor anchor, vm.Vector2 offset, {Color color = const Color(0xFFFFFFFF)}) =>
    EmberEntity(name: name)..addComponent(UITextComponent(text: text, fontSize: size, anchor: anchor, offset: offset, color: color));

EmberEntity _button(String name, String text, String action, vm.Vector2 offset, {String hotkey = '', bool enabled = true}) =>
    EmberEntity(name: name, enabled: enabled)
      ..addComponent(UIButtonComponent(
          text: text, action: action, hotkey: hotkey, anchor: EmberAnchor.center, offset: offset, size: vm.Vector2(220, 46), color: const Color(0xFFFDE68A)));

EmberScene buildStoryScene() {
  final scene = EmberScene(name: StoryTemplate.story);
  scene.addEntity(_camera());
  scene.addEntity(EmberEntity(name: 'Story')
    ..addComponent(StoryPlayerComponent(storyFile: StoryTemplate.storyFile, titleScene: StoryTemplate.title, saveKey: 'lastember'))
    ..addComponent(ScriptComponent(scriptName: 'story_effects.ember')));
  return scene;
}

EmberScene buildStoryTitle() {
  final scene = EmberScene(name: StoryTemplate.title);
  scene.addEntity(_camera());
  scene.addEntity(EmberEntity(name: 'Backdrop')
    ..addComponent(UIImageComponent(assetPath: '${StoryTemplate.art}/hill.png', anchor: EmberAnchor.center, offset: vm.Vector2.zero(), size: vm.Vector2(960, 540))));
  scene.addEntity(EmberEntity(name: 'Title')..addComponent(ScriptComponent(scriptName: 'story_title.ember')));
  scene
    ..addEntity(_text('Logo', 'THE LAST EMBER', 58, EmberAnchor.topCenter, vm.Vector2(0, 70), color: const Color(0xFFFDE68A)))
    ..addEntity(_text('Tagline', 'A short visual novel. One night, one dying fire, four endings.', 16, EmberAnchor.topCenter, vm.Vector2(0, 146),
        color: const Color(0xFFE2E8F0)))
    ..addEntity(_button('NewButton', 'New story', 'new', vm.Vector2(0, 10), hotkey: 'Enter'))
    ..addEntity(_button('ContinueButton', 'Continue', 'continue', vm.Vector2(0, 66), enabled: false))
    ..addEntity(_button('LoadButton', 'Load', 'load', vm.Vector2(0, 122)))
    ..addEntity(_text('EndingsText', 'Endings found: 0 / 4', 14, EmberAnchor.bottomCenter, vm.Vector2(0, -18), color: const Color(0xFFCBD5E1)));
  return scene;
}
