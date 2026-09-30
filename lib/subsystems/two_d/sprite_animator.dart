import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import 'flame_components.dart';

/// One named animation on a sprite sheet: frames [start]..[start]+[count]-1.
class SpriteClip {
  final String name;
  final int start;
  final int count;
  final double fps;
  final bool loop;

  const SpriteClip(this.name, this.start, this.count, {this.fps = 8, this.loop = true});

  @override
  String toString() {
    final range = count > 1 ? '$start-${start + count - 1}' : '$start';
    return '$name=$range@${fps.toStringAsFixed(fps == fps.roundToDouble() ? 0 : 1)}${loop ? '' : '!'}';
  }
}

/// Plays named clips on the entity's Flame Sprite (sheet frames).
///
/// Clips are written as text so they can be edited in the Inspector:
/// `idle=0-1@3; run=2-4@12; jump=5; die=6@1!` — `name=first-last@fps`,
/// a trailing `!` plays once and holds the last frame.
///
/// From a script: `getComponent<SpriteAnimatorComponent>()?.play('run')`.
class SpriteAnimatorComponent extends EmberComponent {
  final List<SpriteClip> clips = [];
  String defaultClip;

  String _current = '';
  double _time = 0;

  SpriteAnimatorComponent({String clips = 'idle=0', this.defaultClip = 'idle'}) {
    clipSpec = clips;
  }

  /// The clip list in text form (see class docs).
  String get clipSpec => clips.join('; ');
  set clipSpec(String spec) {
    clips
      ..clear()
      ..addAll(parseClips(spec));
    notifyListeners();
  }

  /// Parses `idle=0-1@3; run=2-4@12; jump=5; die=6@1!`. Bad entries are skipped.
  static List<SpriteClip> parseClips(String spec) {
    final out = <SpriteClip>[];
    for (final part in spec.split(RegExp(r'[;,\n]'))) {
      final m = RegExp(r'^\s*([\w\- ]+?)\s*=\s*(\d+)(?:\s*-\s*(\d+))?(?:\s*@\s*([\d.]+))?\s*(!)?\s*$').firstMatch(part);
      if (m == null) continue;
      final a = int.parse(m.group(2)!);
      final b = m.group(3) != null ? int.parse(m.group(3)!) : a;
      out.add(SpriteClip(
        m.group(1)!.trim(),
        a < b ? a : b,
        (b - a).abs() + 1,
        fps: double.tryParse(m.group(4) ?? '') ?? 8,
        loop: m.group(5) == null,
      ));
    }
    return out;
  }

  String get currentClip => _current;

  /// True when a play-once clip has reached its last frame.
  bool get isFinished {
    final clip = _clip(_current);
    return clip != null && !clip.loop && _time * clip.fps >= clip.count - 1;
  }

  bool hasClip(String name) => _clip(name) != null;

  SpriteClip? _clip(String name) {
    for (final c in clips) {
      if (c.name == name) return c;
    }
    return null;
  }

  /// Switches to [name]. Calling it every frame with the same name is fine;
  /// the clip only restarts when it changes (or when [restart] is true).
  void play(String name, {bool restart = false}) {
    if (name == _current && !restart) return;
    _current = name;
    _time = 0;
    _apply();
  }

  @override
  void onStart() {
    if (_current.isEmpty) play(defaultClip);
  }

  @override
  void onUpdate(double dt) {
    if (_current.isEmpty) play(defaultClip);
    _time += dt;
    _apply();
  }

  void _apply() {
    final clip = _clip(_current);
    final sprite = entity?.getComponent<FlameSpriteComponent>();
    if (clip == null || sprite == null) return;
    var i = (_time * clip.fps).floor();
    i = clip.loop ? i % clip.count : (i >= clip.count ? clip.count - 1 : i);
    sprite.frame = clip.start + i;
  }

  @override
  String get displayName => 'Sprite Animator';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<String>(
          name: 'clips',
          label: 'Clips (name=frames@fps)',
          type: InspectableType.string,
          getter: () => clipSpec,
          setter: (v) => clipSpec = v,
          tooltip: 'e.g. idle=0-1@3; run=2-4@12; jump=5; die=6@1!',
        ),
        InspectableProperty<String>(
          name: 'defaultClip',
          label: 'Default Clip',
          type: InspectableType.options,
          getter: () => defaultClip,
          setter: (v) {
            defaultClip = v;
            notifyListeners();
          },
          options: clips.map((c) => c.name).toList(),
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {'clips': clipSpec, 'defaultClip': defaultClip};

  @override
  void fromJson(Map<String, dynamic> json) {
    clipSpec = json['clips'] as String? ?? 'idle=0';
    defaultClip = json['defaultClip'] as String? ?? 'idle';
    notifyListeners();
  }

  @override
  SpriteAnimatorComponent clone() => SpriteAnimatorComponent(clips: clipSpec, defaultClip: defaultClip);
}

void registerSpriteAnimator() {
  ComponentRegistry.register('Sprite Animator', (json) => SpriteAnimatorComponent()..fromJson(json));
}
