import 'package:flutter/material.dart';
import '../controllers/message_controller.dart';
import '../theme/app_theme.dart';

/// Latency line chart — reference DIAGS screen (green trace, T-60s → NOW).
class LatencyPerHopPanel extends StatelessWidget {
  const LatencyPerHopPanel({
    super.key,
    this.samples = const [],
  });

  final List<int> samples;

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
                    samples.isEmpty ? 'Not enough data' : 'CUR: ${samples.last}ms',
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
              child: samples.isEmpty
                  ? const Center(child: _EmptyMetricText('Not enough data'))
                  : CustomPaint(painter: _LatencyLinePainter(samples: samples)),
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
  _LatencyLinePainter({required this.samples});

  final List<int> samples;

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
    final maxSample = samples.reduce((a, b) => a > b ? a : b).clamp(1, 100000);
    for (var i = 0; i < samples.length; i++) {
      final x = samples.length == 1 ? size.width : size.width * i / (samples.length - 1);
      final normalized = (samples[i] / maxSample).clamp(0.0, 1.0);
      final y = size.height * (1 - normalized);
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
      oldDelegate.samples != samples;
}

/// Battery drain step chart — reference (grey steps, %/hr).
class BatteryDrainPanel extends StatelessWidget {
  const BatteryDrainPanel({super.key, this.meshImpactPercentPerHour});

  final double? meshImpactPercentPerHour;

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
                  child: Text(
                    meshImpactPercentPerHour == null
                        ? 'Not enough data'
                        : 'CUR: ${meshImpactPercentPerHour!.toStringAsFixed(1)}%',
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
              child: Center(
                child: _EmptyMetricText(
                  meshImpactPercentPerHour == null
                      ? 'Not enough data'
                      : 'Mesh impact ${meshImpactPercentPerHour!.toStringAsFixed(1)}%/hr',
                ),
              ),
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

/// Routing events table — reference (TIMESTAMP / PAYLOAD / STATUS).
class RoutingEventsLogPanel extends StatelessWidget {
  const RoutingEventsLogPanel({super.key, required this.events});

  final List<RoutingEvent> events;

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
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: _EmptyMetricText('No routing events yet'),
              )
            else
              for (final r in events) _LogDataRow(row: r),
          ],
        ),
      ),
    );
  }
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

  final RoutingEvent row;

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
              _formatTime(row.timestamp),
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

  String _formatTime(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    final s = value.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _EmptyMetricText extends StatelessWidget {
  const _EmptyMetricText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: LocalMeshColors.textSecondary,
        ),
      );
}
