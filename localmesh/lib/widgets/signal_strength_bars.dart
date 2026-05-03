import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Four-bar RSSI-style indicator (0–4 filled).
class SignalStrengthBars extends StatelessWidget {
  const SignalStrengthBars({
    super.key,
    required this.level,
    this.max = 4,
  }) : assert(level >= 0 && level <= max);

  /// Number of bars to show filled (0–max).
  final int level;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(max, (i) {
        final h = 4.0 + i * 3.0;
        final on = i < level;
        return Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Container(
            width: 4,
            height: h,
            decoration: BoxDecoration(
              color: on
                  ? LocalMeshColors.accent
                  : LocalMeshColors.borderMuted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      }),
    );
  }
}
