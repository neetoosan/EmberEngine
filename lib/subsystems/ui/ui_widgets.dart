import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/assets.dart';
import '../../core/component.dart';
import '../../core/engine_loop.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/input.dart';
import '../../core/scene.dart';
import '../../core/transform2d.dart';
import 'dialogue.dart';
import 'ui_text.dart';

/// Shared layout for screen-space UI: an [anchor] point on the screen, an
/// [offset] in design pixels, and a [size]; the element's own box is anchored
/// at the same relative point (top-right anchor → element hangs down-left).
mixin UILayout on EmberComponent {
  EmberAnchor anchor = EmberAnchor.topLeft;
  vm.Vector2 offset = vm.Vector2(16, 16);
  vm.Vector2 size = vm.Vector2(120, 32);

  Rect layoutRect(Rect view, double scale) {
    final a = anchor.normalizedOffset;
    final point = Offset(view.left + view.width * a.x + offset.x * scale, view.top + view.height * a.y + offset.y * scale);
    final w = size.x * scale, h = size.y * scale;
    return Rect.fromLTWH(point.dx - w * a.x, point.dy - h * a.y, w, h);
  }

  List<InspectableProperty> get layoutProperties => [
        InspectableProperty<EmberAnchor>(
          name: 'anchor',
          label: 'Screen Anchor',
          type: InspectableType.anchor,
          getter: () => anchor,
          setter: (v) {
            anchor = v;
            notifyListeners();
          },
        ),
        InspectableProperty<vm.Vector2>(
          name: 'offset',
          label: 'Offset',
          type: InspectableType.vector2,
          getter: () => offset,
          setter: (v) {
            offset = v;
            notifyListeners();
          },
        ),
        InspectableProperty<vm.Vector2>(
          name: 'size',
          label: 'Size',
          type: InspectableType.vector2,
          getter: () => size,
          setter: (v) {
            size = v;
            notifyListeners();
          },
        ),
      ];

  Map<String, dynamic> layoutJson() => {
        'anchor': anchor.name,
        'offset': [offset.x, offset.y],
        'size': [size.x, size.y],
      };

  void readLayout(Map<String, dynamic> json) {
    anchor = EmberAnchor.values.firstWhere((a) => a.name == json['anchor'], orElse: () => EmberAnchor.topLeft);
    vm.Vector2 v2(Object? raw, vm.Vector2 d) =>
        raw is List && raw.length == 2 ? vm.Vector2((raw[0] as num).toDouble(), (raw[1] as num).toDouble()) : d;
    offset = v2(json['offset'], vm.Vector2(16, 16));
    size = v2(json['size'], vm.Vector2(120, 32));
  }
}

/// A picture on the screen. With [count] > 1 it draws a row of icons, the
/// first [filled] using [frame] and the rest [emptyFrame] — e.g. hearts.
class UIImageComponent extends EmberComponent with UILayout {
  String assetPath;
  int columns;
  int rows;
  int frame;
  int emptyFrame;
  int count;
  int filled;
  double spacing;

  UIImageComponent({
    this.assetPath = '',
    this.columns = 1,
    this.rows = 1,
    this.frame = 0,
    this.emptyFrame = 0,
    this.count = 1,
    int? filled,
    this.spacing = 4,
    EmberAnchor anchor = EmberAnchor.topLeft,
    vm.Vector2? offset,
    vm.Vector2? size,
  }) : filled = filled ?? count {
    this.anchor = anchor;
    if (offset != null) this.offset = offset;
    if (size != null) this.size = size;
  }

  void paint(Canvas canvas, Rect view, double scale) {
    final image = EmberAssets.instance.image(assetPath);
    if (image == null) return;
    final first = layoutRect(view, scale);
    final cols = columns < 1 ? 1 : columns;
    final cw = image.width / cols;
    final ch = image.height / (rows < 1 ? 1 : rows);
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    for (var i = 0; i < count; i++) {
      final f = i < filled ? frame : emptyFrame;
      final src = Rect.fromLTWH((f % cols) * cw, (f ~/ cols) * ch, cw, ch);
      canvas.drawImageRect(image, src, first.shift(Offset(i * (first.width + spacing * scale), 0)), paint);
    }
  }

  @override
  String get displayName => 'UI Image';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<String>(
          name: 'assetPath',
          label: 'Image',
          type: InspectableType.string,
          getter: () => assetPath,
          setter: (v) {
            assetPath = v;
            notifyListeners();
          },
        ),
        InspectableProperty<int>(
          name: 'count',
          label: 'Repeat Count',
          type: InspectableType.integer,
          getter: () => count,
          setter: (v) {
            count = v.clamp(0, 64);
            notifyListeners();
          },
          min: 0,
          step: 1,
        ),
        ...layoutProperties,
      ];

  @override
  Map<String, dynamic> toJson() => {
        ...layoutJson(),
        'assetPath': assetPath,
        'columns': columns,
        'rows': rows,
        'frame': frame,
        'emptyFrame': emptyFrame,
        'count': count,
        'filled': filled,
        'spacing': spacing,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    readLayout(json);
    assetPath = json['assetPath'] as String? ?? '';
    columns = (json['columns'] as num?)?.toInt() ?? 1;
    rows = (json['rows'] as num?)?.toInt() ?? 1;
    frame = (json['frame'] as num?)?.toInt() ?? 0;
    emptyFrame = (json['emptyFrame'] as num?)?.toInt() ?? 0;
    count = (json['count'] as num?)?.toInt() ?? 1;
    filled = (json['filled'] as num?)?.toInt() ?? count;
    spacing = (json['spacing'] as num?)?.toDouble() ?? 4;
    notifyListeners();
  }

  @override
  UIImageComponent clone() => UIImageComponent()..fromJson(toJson());
}

/// A fill bar (health, stamina, XP, boss health).
class UIBarComponent extends EmberComponent with UILayout {
  double value;
  double max;
  Color fillColor;
  Color backColor;
  String label;

  UIBarComponent({
    this.value = 1,
    this.max = 1,
    this.fillColor = const Color(0xFFEF4444),
    this.backColor = const Color(0xCC111318),
    this.label = '',
    EmberAnchor anchor = EmberAnchor.topLeft,
    vm.Vector2? offset,
    vm.Vector2? size,
  }) {
    this.anchor = anchor;
    if (offset != null) this.offset = offset;
    this.size = size ?? vm.Vector2(160, 12);
  }

  void paint(Canvas canvas, Rect view, double scale) {
    final r = layoutRect(view, scale);
    final radius = Radius.circular(r.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(r, radius), Paint()..color = backColor);
    final f = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    if (f > 0) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(r.left, r.top, r.width * f, r.height), radius), Paint()..color = fillColor);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, radius),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * scale
        ..color = const Color(0xCC000000),
    );
    if (label.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: label, style: TextStyle(color: Colors.white, fontSize: r.height * 0.75, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
    }
  }

  @override
  String get displayName => 'UI Bar';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<double>(
          name: 'value',
          label: 'Value',
          type: InspectableType.number,
          getter: () => value,
          setter: (v) {
            value = v;
            notifyListeners();
          },
        ),
        InspectableProperty<double>(
          name: 'max',
          label: 'Max',
          type: InspectableType.number,
          getter: () => max,
          setter: (v) {
            max = v;
            notifyListeners();
          },
        ),
        InspectableProperty<Color>(
          name: 'fillColor',
          label: 'Fill Color',
          type: InspectableType.color,
          getter: () => fillColor,
          setter: (v) {
            fillColor = v;
            notifyListeners();
          },
        ),
        InspectableProperty<String>(
          name: 'label',
          label: 'Label',
          type: InspectableType.string,
          getter: () => label,
          setter: (v) {
            label = v;
            notifyListeners();
          },
        ),
        ...layoutProperties,
      ];

  @override
  Map<String, dynamic> toJson() => {
        ...layoutJson(),
        'value': value,
        'max': max,
        'fillColor': fillColor.toARGB32(),
        'backColor': backColor.toARGB32(),
        'label': label,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    readLayout(json);
    value = (json['value'] as num?)?.toDouble() ?? 1;
    max = (json['max'] as num?)?.toDouble() ?? 1;
    fillColor = Color(json['fillColor'] as int? ?? 0xFFEF4444);
    backColor = Color(json['backColor'] as int? ?? 0xCC111318);
    label = json['label'] as String? ?? '';
    notifyListeners();
  }

  @override
  UIBarComponent clone() => UIBarComponent()..fromJson(toJson());
}

/// A clickable button. Clicking (or pressing [hotkey], e.g. `Enter`) sends
/// [action] to every script's `onUIAction`. Built-in actions:
/// `level:<scene name>` loads a level, `restart` restarts the current one.
class UIButtonComponent extends EmberComponent with UILayout {
  String text;
  String action;
  String hotkey;
  Color color;
  Color textColor;
  double fontSize;

  UIButtonComponent({
    this.text = 'Button',
    this.action = '',
    this.hotkey = '',
    this.color = const Color(0xFFF59E0B),
    this.textColor = const Color(0xFF1B1420),
    this.fontSize = 16,
    EmberAnchor anchor = EmberAnchor.center,
    vm.Vector2? offset,
    vm.Vector2? size,
  }) {
    this.anchor = anchor;
    this.offset = offset ?? vm.Vector2.zero();
    this.size = size ?? vm.Vector2(180, 40);
  }

  void paint(Canvas canvas, Rect view, double scale, {required bool hovered}) {
    final r = layoutRect(view, scale);
    final rrect = RRect.fromRectAndRadius(r, Radius.circular(8 * scale));
    canvas.drawRRect(rrect.shift(Offset(0, 3 * scale)), Paint()..color = const Color(0x66000000));
    canvas.drawRRect(rrect, Paint()..color = hovered ? Color.lerp(color, Colors.white, 0.25)! : color);
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: textColor, fontSize: fontSize * scale, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: r.width);
    tp.paint(canvas, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
  }

  LogicalKeyboardKey? get hotkeyKey {
    if (hotkey.isEmpty) return null;
    final want = hotkey.toLowerCase();
    for (final k in LogicalKeyboardKey.knownLogicalKeys) {
      if (k.keyLabel.toLowerCase() == want || (k.debugName?.toLowerCase() ?? '') == want) return k;
    }
    return null;
  }

  @override
  String get displayName => 'UI Button';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<String>(
          name: 'text',
          label: 'Text',
          type: InspectableType.string,
          getter: () => text,
          setter: (v) {
            text = v;
            notifyListeners();
          },
        ),
        InspectableProperty<String>(
          name: 'action',
          label: 'Action',
          type: InspectableType.string,
          getter: () => action,
          setter: (v) {
            action = v;
            notifyListeners();
          },
          tooltip: 'Sent to scripts (onUIAction). level:<name> loads a level; restart restarts.',
        ),
        InspectableProperty<String>(
          name: 'hotkey',
          label: 'Hotkey',
          type: InspectableType.string,
          getter: () => hotkey,
          setter: (v) {
            hotkey = v;
            notifyListeners();
          },
        ),
        InspectableProperty<Color>(
          name: 'color',
          label: 'Color',
          type: InspectableType.color,
          getter: () => color,
          setter: (v) {
            color = v;
            notifyListeners();
          },
        ),
        ...layoutProperties,
      ];

  @override
  Map<String, dynamic> toJson() => {
        ...layoutJson(),
        'text': text,
        'action': action,
        'hotkey': hotkey,
        'color': color.toARGB32(),
        'textColor': textColor.toARGB32(),
        'fontSize': fontSize,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    readLayout(json);
    text = json['text'] as String? ?? '';
    action = json['action'] as String? ?? '';
    hotkey = json['hotkey'] as String? ?? '';
    color = Color(json['color'] as int? ?? 0xFFF59E0B);
    textColor = Color(json['textColor'] as int? ?? 0xFF1B1420);
    fontSize = (json['fontSize'] as num?)?.toDouble() ?? 16;
    notifyListeners();
  }

  @override
  UIButtonComponent clone() => UIButtonComponent()..fromJson(toJson());
}

/// Draws and runs all screen-space UI (images, bars, buttons, text,
/// dialogue, screen fade) and routes clicks to buttons.
class UIRenderer {
  /// Full-screen fade to black, 0 (none) .. 1 (black). Animate with EmberTween.
  static double fade = 0;

  /// Last pointer position in screen pixels (for button hover), or null.
  static Offset? pointer;

  static bool _visible(EmberComponent c) => c.enabled && (c.entity?.enabled ?? false);

  static void paintAll(Canvas canvas, Rect view, double scale, EmberScene scene) {
    for (final img in scene.componentsOf<UIImageComponent>()) {
      if (_visible(img)) img.paint(canvas, view, scale);
    }
    for (final bar in scene.componentsOf<UIBarComponent>()) {
      if (_visible(bar)) bar.paint(canvas, view, scale);
    }
    final p = pointer;
    for (final b in scene.componentsOf<UIButtonComponent>()) {
      if (_visible(b)) b.paint(canvas, view, scale, hovered: p != null && b.layoutRect(view, scale).contains(p));
    }
    UITextComponent.paintAll(canvas, view, scale, scene);
    DialogueSystem.instance.paint(canvas, view, scale);
    if (fade > 0) {
      canvas.drawRect(view, Paint()..color = Color.fromRGBO(0, 0, 0, fade.clamp(0.0, 1.0)));
    }
  }

  /// The top-most visible button under [point], if any.
  static UIButtonComponent? buttonAt(EmberScene scene, Rect view, double scale, Offset point) {
    UIButtonComponent? hit;
    for (final b in scene.componentsOf<UIButtonComponent>()) {
      if (_visible(b) && b.layoutRect(view, scale).contains(point)) hit = b;
    }
    return hit;
  }

  /// Runs a button action: built-ins first, then every script's onUIAction.
  static void dispatch(EmberScene scene, String action) {
    if (action.isEmpty) return;
    final engine = EmberEngine.instance;
    if (action.startsWith('level:')) {
      engine.loadLevel(action.substring(6));
    } else if (action == 'restart') {
      engine.restartScene();
    }
    for (final e in scene.allEntities) {
      e.notifyScripts((s) => s.onUIAction(action));
    }
  }

  /// Real-time per-frame work: button hotkeys.
  static void update(EmberScene scene) {
    for (final b in scene.componentsOf<UIButtonComponent>()) {
      if (!_visible(b)) continue;
      final key = b.hotkeyKey;
      if (key != null && Input.isKeyJustPressed(key)) {
        dispatch(scene, b.action);
        return;
      }
    }
  }
}

void registerUIWidgets() {
  ComponentRegistry.register('UI Image', (json) => UIImageComponent()..fromJson(json));
  ComponentRegistry.register('UI Bar', (json) => UIBarComponent()..fromJson(json));
  ComponentRegistry.register('UI Button', (json) => UIButtonComponent()..fromJson(json));
}

