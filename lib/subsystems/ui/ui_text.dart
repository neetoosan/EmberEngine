import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../core/component.dart';
import '../../core/entity.dart';
import '../../core/inspectable.dart';
import '../../core/scene.dart';
import '../../core/transform2d.dart';

/// Text drawn on top of the game view (score, lives, "Game Over"), fixed to
/// the screen rather than the world. Works in 2D and 3D scenes.
///
/// [anchor] picks the screen point (e.g. top-center) and [offset] nudges it,
/// in design pixels (see Camera 2D). Scripts change [text] at runtime.
class UITextComponent extends EmberComponent {
  String _text;
  double fontSize;
  Color color;
  EmberAnchor anchor;
  vm.Vector2 offset;
  bool bold;

  /// Dark outline so text stays readable on any background.
  bool outline;

  UITextComponent({
    this._text = 'Text',
    this.fontSize = 24.0,
    this.color = Colors.white,
    this.anchor = EmberAnchor.topCenter,
    vm.Vector2? offset,
    this.bold = true,
    this.outline = true,
  }) : offset = offset ?? vm.Vector2(0, 16);

  String get text => _text;
  set text(String value) {
    if (value == _text) return;
    _text = value;
    notifyListeners();
  }

  /// Draws every enabled UI text in [scene] inside [view] (screen pixels);
  /// [scale] converts design pixels to screen pixels.
  static void paintAll(Canvas canvas, Rect view, double scale, EmberScene scene) {
    for (final t in scene.componentsOf<UITextComponent>()) {
      if (t.enabled && t.text.isNotEmpty && (t.entity?.enabled ?? false)) t._paint(canvas, view, scale);
    }
  }

  void _paint(Canvas canvas, Rect view, double scale) {
    final style = TextStyle(
      fontSize: fontSize * scale,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      height: 1.1,
    );
    final a = anchor.normalizedOffset;
    final align = a.x < 0.25 ? TextAlign.left : (a.x > 0.75 ? TextAlign.right : TextAlign.center);

    TextPainter layout(Paint? foreground, Color? fill) => TextPainter(
          text: TextSpan(text: _text, style: style.copyWith(foreground: foreground, color: fill)),
          textAlign: align,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: view.width);

    final fillPainter = layout(null, color);
    final point = Offset(
      view.left + view.width * a.x + offset.x * scale,
      view.top + view.height * a.y + offset.y * scale,
    );
    // Anchor the text box at the same relative point (top-center text hangs below the point, etc.)
    final topLeft = point - Offset(fillPainter.width * a.x, fillPainter.height * a.y);

    if (outline) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (fontSize * scale / 8).clamp(1.5, 8.0)
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xE6000000);
      layout(stroke, null).paint(canvas, topLeft);
    }
    fillPainter.paint(canvas, topLeft);
  }

  @override
  String get displayName => 'UI Text';

  @override
  List<InspectableProperty> get inspectableProperties => [
        InspectableProperty<String>(
          name: 'text',
          label: 'Text',
          type: InspectableType.string,
          getter: () => _text,
          setter: (val) => text = val,
        ),
        InspectableProperty<double>(
          name: 'fontSize',
          label: 'Font Size',
          type: InspectableType.number,
          getter: () => fontSize,
          setter: (val) {
            fontSize = val.clamp(4.0, 400.0);
            notifyListeners();
          },
          min: 4,
          max: 400,
          step: 1,
        ),
        InspectableProperty<Color>(
          name: 'color',
          label: 'Color',
          type: InspectableType.color,
          getter: () => color,
          setter: (val) {
            color = val;
            notifyListeners();
          },
        ),
        InspectableProperty<EmberAnchor>(
          name: 'anchor',
          label: 'Screen Anchor',
          type: InspectableType.anchor,
          getter: () => anchor,
          setter: (val) {
            anchor = val;
            notifyListeners();
          },
        ),
        InspectableProperty<vm.Vector2>(
          name: 'offset',
          label: 'Offset',
          type: InspectableType.vector2,
          getter: () => offset,
          setter: (val) {
            offset = val;
            notifyListeners();
          },
          step: 1,
        ),
        InspectableProperty<bool>(
          name: 'bold',
          label: 'Bold',
          type: InspectableType.boolean,
          getter: () => bold,
          setter: (val) {
            bold = val;
            notifyListeners();
          },
        ),
        InspectableProperty<bool>(
          name: 'outline',
          label: 'Outline',
          type: InspectableType.boolean,
          getter: () => outline,
          setter: (val) {
            outline = val;
            notifyListeners();
          },
        ),
      ];

  @override
  Map<String, dynamic> toJson() => {
        'text': _text,
        'fontSize': fontSize,
        'color': color.toARGB32(),
        'anchor': anchor.name,
        'offset': [offset.x, offset.y],
        'bold': bold,
        'outline': outline,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    _text = json['text'] as String? ?? '';
    fontSize = (json['fontSize'] as num?)?.toDouble() ?? 24.0;
    color = Color(json['color'] as int? ?? 0xFFFFFFFF);
    anchor = EmberAnchor.values.firstWhere((a) => a.name == json['anchor'], orElse: () => EmberAnchor.topCenter);
    final o = json['offset'] as List<dynamic>?;
    offset = o == null ? vm.Vector2(0, 16) : vm.Vector2((o[0] as num).toDouble(), (o[1] as num).toDouble());
    bold = json['bold'] as bool? ?? true;
    outline = json['outline'] as bool? ?? true;
    notifyListeners();
  }

  @override
  UITextComponent clone() => UITextComponent(
        text: _text,
        fontSize: fontSize,
        color: color,
        anchor: anchor,
        offset: offset.clone(),
        bold: bold,
        outline: outline,
      );
}

/// Registers UI components for scene deserialization.
void registerUIComponents() {
  ComponentRegistry.register('UI Text', (json) => UITextComponent()..fromJson(json));
}
