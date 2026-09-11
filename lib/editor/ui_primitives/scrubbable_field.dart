import 'package:flutter/material.dart';
import '../theme/ember_theme.dart';

/// A sleek numerical input field that allows dragging horizontally to scrub values,
/// or clicking directly to type in a number.
class ScrubbableField extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double step;
  final double? min;
  final double? max;
  final Color? labelColor;
  final int precision;

  const ScrubbableField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.step = 0.1,
    this.min,
    this.max,
    this.labelColor,
    this.precision = 2,
  });

  @override
  State<ScrubbableField> createState() => _ScrubbableFieldState();
}

class _ScrubbableFieldState extends State<ScrubbableField> {
  bool _isEditing = false;
  late TextEditingController _textController;
  late FocusNode _focusNode;
  double _dragAccumulator = 0.0;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: _formatValue(widget.value));
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        _commitText();
      }
    });
  }

  @override
  void didUpdateWidget(covariant ScrubbableField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && oldWidget.value != widget.value) {
      _textController.text = _formatValue(widget.value);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _formatValue(double val) {
    if (val == val.roundToDouble() && widget.precision == 0) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(widget.precision);
  }

  void _commitText() {
    final parsed = double.tryParse(_textController.text);
    if (parsed != null) {
      var clamped = parsed;
      if (widget.min != null) clamped = clamped.clamp(widget.min!, double.infinity);
      if (widget.max != null) clamped = clamped.clamp(double.negativeInfinity, widget.max!);
      widget.onChanged(clamped);
    } else {
      _textController.text = _formatValue(widget.value);
    }
    setState(() => _isEditing = false);
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    _dragAccumulator += details.delta.dx * widget.step;
    if (_dragAccumulator.abs() >= widget.step * 0.5) {
      var newVal = widget.value + _dragAccumulator;
      if (widget.min != null) newVal = newVal.clamp(widget.min!, double.infinity);
      if (widget.max != null) newVal = newVal.clamp(double.negativeInfinity, widget.max!);
      widget.onChanged(newVal);
      _dragAccumulator = 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.labelColor ?? EmberTheme.textSecondary;

    return Container(
      height: 24,
      decoration: BoxDecoration(
        color: EmberTheme.surfaceCard,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _isEditing ? EmberTheme.accentEmber : EmberTheme.borderSubtle,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Scrubbable Label Handle
          GestureDetector(
            onHorizontalDragUpdate: _handleHorizontalDragUpdate,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: Container(
                width: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(3)),
                ),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),

          // Numeric Display or Text Input
          Expanded(
            child: _isEditing
                ? TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    keyboardType: TextInputType.number,
                    style: EmberTheme.codeStyle.copyWith(fontSize: 11),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    ),
                    onSubmitted: (_) => _commitText(),
                  )
                : GestureDetector(
                    onTap: () {
                      setState(() {
                        _isEditing = true;
                        _textController.text = widget.value.toString();
                        _focusNode.requestFocus();
                      });
                    },
                    onHorizontalDragUpdate: _handleHorizontalDragUpdate,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _formatValue(widget.value),
                          style: EmberTheme.codeStyle.copyWith(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
