import 'package:flutter/material.dart';

class ExpressiveCard extends StatefulWidget {
  const ExpressiveCard({
    super.key,
    required this.child,
    this.selected = false,
    this.selectedColor,
    this.onTap,
    this.elevation = 0,
  });

  final Widget child;
  final bool selected;
  final Color? selectedColor;
  final VoidCallback? onTap;
  final double elevation;

  @override
  State<ExpressiveCard> createState() => _ExpressiveCardState();
}

class _ExpressiveCardState extends State<ExpressiveCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _elevation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _elevation = Tween<double>(begin: 0, end: 4).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    if (widget.selected) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(ExpressiveCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      if (widget.selected) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = widget.selected
        ? (widget.selectedColor ?? theme.colorScheme.primaryContainer)
        : theme.colorScheme.surfaceContainerLow;
    final borderColor = widget.selected
        ? (widget.selectedColor ?? theme.colorScheme.primary).withValues(alpha: 0.5)
        : theme.colorScheme.outlineVariant;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return Transform.scale(
          scale: _scale.value,
          child: Material(
            color: cardColor,
            borderRadius: BorderRadius.circular(22),
            elevation: _elevation.value,
            shadowColor: widget.selected
                ? (widget.selectedColor ?? theme.colorScheme.primary)
                    .withValues(alpha: 0.3)
                : Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(22),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: borderColor,
                    width: widget.selected ? 1.5 : 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
