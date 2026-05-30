import 'package:expressive_loading_indicator/expressive_loading_indicator.dart'
    as expressive;
import 'package:flutter/material.dart';

class ExpressiveLoadingIndicator extends StatelessWidget {
  const ExpressiveLoadingIndicator({
    super.key,
    this.size = 44,
    this.strokeWidth = 4.5,
    this.semanticsLabel = 'Loading',
  });

  final double size;
  final double strokeWidth;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final compact = size <= 24 || strokeWidth <= 2;
    final iconColor = IconTheme.of(context).color;
    final progressColor = ProgressIndicatorTheme.of(context).color;
    final color = compact && iconColor != null
        ? iconColor
        : progressColor ?? Theme.of(context).colorScheme.primary;
    return expressive.ExpressiveLoadingIndicator(
      color: color,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      semanticsLabel: semanticsLabel,
    );
  }
}
