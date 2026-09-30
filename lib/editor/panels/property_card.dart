import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;
import '../../core/component.dart';
import '../../core/inspectable.dart';
import '../../core/transform2d.dart';
import '../theme/ember_theme.dart';
import '../ui_primitives/anchor_selector.dart';
import '../ui_primitives/compact_accordion.dart';
import '../ui_primitives/scrubbable_field.dart';
import '../ui_primitives/vector2_field.dart';

/// Inspector card built from a component's [EmberComponent.inspectableProperties].
/// Used for components that don't have a hand-made card (Camera 2D, UI Text,
/// and any new component), so everything added to the engine is editable.
class GenericComponentCard extends StatelessWidget {
  final EmberComponent component;
  final IconData icon;

  /// Called after any edit so the panel can rebuild.
  final VoidCallback onChanged;

  const GenericComponentCard({
    super.key,
    required this.component,
    required this.onChanged,
    this.icon = Icons.tune,
  });

  @override
  Widget build(BuildContext context) {
    final props = component.inspectableProperties;
    return CompactAccordion(
      title: component.displayName,
      icon: icon,
      isEnabled: component.enabled,
      onEnableChanged: (val) {
        component.enabled = val;
        onChanged();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in props) ...[
            _buildProperty(p),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _label(InspectableProperty p) => Tooltip(
        message: p.tooltip ?? '',
        child: Text('${p.label}:', style: const TextStyle(fontSize: 11, color: EmberTheme.textSecondary)),
      );

  void _set(InspectableProperty p, Object? value) {
    p.setValue(value);
    onChanged();
  }

  Widget _buildProperty(InspectableProperty p) {
    final value = p.getValue();
    switch (p.type) {
      case InspectableType.number:
        return ScrubbableField(
          label: p.label,
          value: (value as num).toDouble(),
          step: p.step,
          min: p.min,
          max: p.max,
          onChanged: (v) => _set(p, v),
        );
      case InspectableType.integer:
        return ScrubbableField(
          label: p.label,
          value: (value as num).toDouble(),
          step: p.step < 1 ? 1 : p.step,
          min: p.min,
          max: p.max,
          precision: 0,
          onChanged: (v) => _set(p, v.round()),
        );
      case InspectableType.boolean:
        return Row(
          children: [
            Expanded(child: _label(p)),
            SizedBox(
              height: 24,
              child: Checkbox(
                value: value as bool,
                activeColor: EmberTheme.accentFlame,
                onChanged: (v) => _set(p, v ?? false),
              ),
            ),
          ],
        );
      case InspectableType.string:
        return _StringPropertyField(
          label: p.label,
          value: value as String,
          onSubmitted: (v) => _set(p, v),
          multiline: p.multiline,
          describe: p.hasDescription ? (v) => p.describeValue(v) ?? '' : null,
        );
      case InspectableType.color:
        return Row(
          children: [
            _label(p),
            const Spacer(),
            ColorSwatchPicker(current: value as Color, onSelected: (c) => _set(p, c)),
          ],
        );
      case InspectableType.vector2:
        return Vector2Field(
          label: p.label,
          value: (value as Vector2).clone(),
          step: p.step,
          onChanged: (v) => _set(p, v),
        );
      case InspectableType.anchor:
        return Row(
          children: [
            _label(p),
            const Spacer(),
            FlameAnchorSelector(currentAnchor: value as EmberAnchor, onSelected: (a) => _set(p, a)),
          ],
        );
      case InspectableType.options:
        return _buildOptions(p, value);
      default:
        return Text('${p.label}: $value', style: const TextStyle(fontSize: 11, color: EmberTheme.textMuted));
    }
  }

  Widget _buildOptions(InspectableProperty p, Object? value) {
    final options = p.options ?? const [];
    // Enum-valued options are shown read-only here (the setter needs the enum type).
    if (value is! String || options.isEmpty) {
      final shown = value is Enum ? value.name : '$value';
      return Row(children: [_label(p), const Spacer(), Text(shown, style: const TextStyle(fontSize: 11))]);
    }
    return Row(
      children: [
        _label(p),
        const Spacer(),
        DropdownButton<String>(
          value: options.contains(value) ? value : null,
          hint: Text(value.isEmpty ? '(none)' : value, style: const TextStyle(fontSize: 11)),
          dropdownColor: EmberTheme.surfaceCard,
          underline: const SizedBox.shrink(),
          isDense: true,
          style: const TextStyle(fontSize: 11, color: EmberTheme.textPrimary),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) {
            if (v != null) _set(p, v);
          },
        ),
      ],
    );
  }
}

/// Small palette of common colours.
class ColorSwatchPicker extends StatelessWidget {
  final Color current;
  final ValueChanged<Color> onSelected;

  const ColorSwatchPicker({super.key, required this.current, required this.onSelected});

  static const colors = [
    Color(0xFFFFFFFF),
    Color(0xFF000000),
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFFFACC15),
    Color(0xFF22C55E),
    Color(0xFF38BDF8),
    Color(0xFF6366F1),
    Color(0xFF4EC0CA),
    Color(0xFF334155),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 3,
      children: [
        for (final c in colors)
          GestureDetector(
            onTap: () => onSelected(c),
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: c.toARGB32() == current.toARGB32() ? EmberTheme.accentFlame : EmberTheme.borderMedium,
                  width: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Text field that commits on Enter or when focus leaves.
class _StringPropertyField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onSubmitted;
  final bool multiline;
  final String Function(String value)? describe;

  const _StringPropertyField({
    required this.label,
    required this.value,
    required this.onSubmitted,
    this.multiline = false,
    this.describe,
  });

  @override
  State<_StringPropertyField> createState() => _StringPropertyFieldState();
}

class _StringPropertyFieldState extends State<_StringPropertyField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _StringPropertyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && widget.value != _controller.text) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    if (_controller.text != widget.value) widget.onSubmitted(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final describe = widget.describe;
    return TextField(
      controller: _controller,
      focusNode: _focus,
      onSubmitted: (_) => _commit(),
      onChanged: describe == null ? null : (_) => setState(() {}),
      minLines: widget.multiline ? 3 : 1,
      maxLines: widget.multiline ? 10 : 1,
      keyboardType: widget.multiline ? TextInputType.multiline : TextInputType.text,
      style: const TextStyle(fontSize: 11, color: EmberTheme.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        labelText: widget.label,
        helperText: describe?.call(_controller.text),
        helperStyle: const TextStyle(fontSize: 10, color: EmberTheme.textSecondary),
        helperMaxLines: 3,
        labelStyle: const TextStyle(fontSize: 11, color: EmberTheme.textSecondary),
        filled: true,
        fillColor: EmberTheme.surfaceCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
      ),
    );
  }
}
