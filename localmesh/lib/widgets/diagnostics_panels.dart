import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Latency line chart — reference DIAGS screen (green trace, T-60s → NOW).
class LatencyPerHopPanel extends StatelessWidget {
  const LatencyPerHopPanel({
    super.key,
    this.currentMs = 24,
  });

  final int currentMs;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'LATENCY_PER_HOP (MS)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          letterSpacing: 1,
                          color: LocalMeshColors.textSecondary,
                        ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: LocalMeshColors.accent),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'CUR: ${currentMs}ms',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: LocalMeshColors.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 100,
              width: double.infinity,
              child: CustomPaint(
                painter: _LatencyLinePainter(seed: currentMs),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'T-60s',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Text(
                  'NOW',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    color: LocalMeshColors.accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LatencyLinePainter extends CustomPainter {
  _LatencyLinePainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = LocalMeshColors.borderMuted.withValues(alpha: 0.35)
      ..strokeWidth = 0.5;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final path = Path();
    final rnd = math.Random(seed);
    const n = 48;
    for (var i = 0; i <= n; i++) {
      final x = size.width * i / n;
      final wave =
          0.5 + 0.45 * math.sin(i * 0.35 + seed * 0.01) + rnd.nextDouble() * 0.08;
      final y = size.height * (1 - wave.clamp(0.08, 0.95));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final line = Paint()
      ..color = LocalMeshColors.accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _LatencyLinePainter oldDelegate) =>
      oldDelegate.seed != seed;
}

/// Battery drain step chart — reference (grey steps, %/hr).
class BatteryDrainPanel extends StatelessWidget {
  const BatteryDrainPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'BATT_DRAIN (%/HR)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          letterSpacing: 1,
                          color: LocalMeshColors.textSecondary,
                        ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: LocalMeshColors.borderMuted),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'CUR: -2.4%',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: LocalMeshColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              width: double.infinity,
              child: CustomPaint(painter: _BatteryStepPainter()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'T-60m',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Text(
                  'NOW',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    color: LocalMeshColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BatteryStepPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..color = LocalMeshColors.borderMuted.withValues(alpha: 0.25)
      ..strokeWidth = 0.5;
    final h = size.height;
    canvas.drawLine(Offset(0, h * 0.7), Offset(size.width, h * 0.7), bg);

    final steps = <double>[0.85, 0.72, 0.68, 0.55, 0.52, 0.48, 0.45];
    final seg = size.width / steps.length;
    final paint = Paint()
      ..color = LocalMeshColors.textSecondary.withValues(alpha: 0.85)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < steps.length; i++) {
      final x0 = i * seg;
      final x1 = (i + 1) * seg;
      final y = h * steps[i];
      canvas.drawLine(Offset(x0, y), Offset(x1, y), paint);
      if (i < steps.length - 1) {
        final yn = h * steps[i + 1];
        canvas.drawLine(Offset(x1, y), Offset(x1, yn), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Routing events table — reference (TIMESTAMP / PAYLOAD / STATUS).
class RoutingEventsLogPanel extends StatelessWidget {
  const RoutingEventsLogPanel({super.key});

  static const _rows = <_LogRow>[
    _LogRow('14:32:01', 'Gossip Forwarded • MSG_ID_782', 'OK'),
    _LogRow('14:31:58', 'Peer Discovery • NODE_A4F9', 'OK'),
    _LogRow('14:31:44', 'Route Failure: Hop Limit Reached', 'DROP'),
    _LogRow('14:31:40', 'Sync Request', 'SYNC'),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'ROUTING_EVENTS_LOG',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          letterSpacing: 1,
                          color: LocalMeshColors.textSecondary,
                        ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: LocalMeshColors.accent),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: LocalMeshColors.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const _LogHeader(),
            const Divider(height: 1, color: LocalMeshColors.borderMuted),
            for (final r in _rows) _LogDataRow(row: r),
          ],
        ),
      ),
    );
  }
}

class _LogRow {
  const _LogRow(this.ts, this.payload, this.status);
  final String ts;
  final String payload;
  final String status;
}

class _LogHeader extends StatelessWidget {
  const _LogHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              'TIME',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                color: LocalMeshColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'EVENT_PAYLOAD',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                color: LocalMeshColors.textSecondary,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              'STATUS',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                color: LocalMeshColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogDataRow extends StatelessWidget {
  const _LogDataRow({required this.row});

  final _LogRow row;

  @override
  Widget build(BuildContext context) {
    final isDrop = row.status == 'DROP';
    final statusColor =
        isDrop ? const Color(0xFFFF6B6B) : LocalMeshColors.accent;
    final payloadStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 9,
      color: isDrop ? const Color(0xFFB85C5C) : Colors.white70,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              row.ts,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                color: LocalMeshColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(row.payload, style: payloadStyle),
          ),
          SizedBox(
            width: 44,
            child: Text(
              row.status,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
