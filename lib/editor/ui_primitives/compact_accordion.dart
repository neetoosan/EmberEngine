import 'package:flutter/material.dart';
import '../theme/ember_theme.dart';

/// Ultra-thin, minimalist accordion header and collapsible body for component cards.
class CompactAccordion extends StatefulWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final bool isInitiallyExpanded;
  final bool isEnabled;
  final ValueChanged<bool>? onEnableChanged;
  final VoidCallback? onRemove;

  const CompactAccordion({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.isInitiallyExpanded = true,
    this.isEnabled = true,
    this.onEnableChanged,
    this.onRemove,
  });

  @override
  State<CompactAccordion> createState() => _CompactAccordionState();
}

class _CompactAccordionState extends State<CompactAccordion> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isInitiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: EmberTheme.surfaceCard,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: EmberTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Icon(
                    _isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                    size: 16,
                    color: EmberTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Icon(widget.icon, size: 13, color: EmberTheme.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: EmberTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.onEnableChanged != null)
                    GestureDetector(
                      onTap: () => widget.onEnableChanged!(!widget.isEnabled),
                      child: Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: widget.isEnabled ? EmberTheme.accentGreen : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: widget.isEnabled ? EmberTheme.accentGreen : EmberTheme.textMuted,
                            width: 1,
                          ),
                        ),
                        child: widget.isEnabled
                            ? const Icon(Icons.check, size: 10, color: Colors.black)
                            : null,
                      ),
                    ),
                  if (widget.onRemove != null)
                    InkWell(
                      onTap: widget.onRemove,
                      borderRadius: BorderRadius.circular(2),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.close, size: 12, color: EmberTheme.textMuted),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Collapsible Body
          if (_isExpanded) ...[
            const Divider(color: EmberTheme.borderSubtle, height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: widget.child,
            ),
          ],
        ],
      ),
    );
  }
}
