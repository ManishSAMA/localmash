import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../controllers/message_controller.dart';
import '../theme/app_theme.dart';

class MeshTopologyCanvas extends StatelessWidget {
  const MeshTopologyCanvas({
    super.key,
    required this.topology,
    this.minHeight = 220,
  });

  final MeshTopologySnapshot topology;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = math.max(minHeight, 200.0);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CustomPaint(
            size: Size(w, h),
            painter: _MeshTopologyPainter(topology),
            child: SizedBox(width: w, height: h),
          ),
        );
      },
    );
  }
}

class _MeshTopologyPainter extends CustomPainter {
  _MeshTopologyPainter(this.topology);

  final MeshTopologySnapshot topology;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = LocalMeshColors.background,
    );
    _drawGrid(canvas, size);

    final ids = topology.nodes.keys.toList(growable: false);
    if (ids.isEmpty) return;

    final positions = _layout(ids, size);
    final active = Paint()
      ..color = LocalMeshColors.accent
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    final relay = Paint()
      ..color = LocalMeshColors.textSecondary.withValues(alpha: 0.7)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;

    for (final link in topology.links) {
      final a = positions[link.fromId];
      final b = positions[link.toId];
      if (a == null || b == null) continue;
      if (link.active) {
        canvas.drawLine(a, b, active);
      } else if (link.relay) {
        _drawDashedLine(canvas, a, b, relay);
      }
    }

    for (final id in ids) {
      final p = positions[id]!;
      final isLocal = id == topology.localId;
      final isolated = !topology.links.any((l) => l.fromId == id || l.toId == id);
      final fill = Paint()
        ..color = isLocal ? LocalMeshColors.accent : LocalMeshColors.surfaceCard;
      final edge = Paint()
        ..color = isolated
            ? LocalMeshColors.textSecondary.withValues(alpha: 0.55)
            : LocalMeshColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = isLocal ? 2.4 : 1.6;
      canvas.drawCircle(p, isLocal ? 8 : 7, fill);
      canvas.drawCircle(p, isLocal ? 8 : 7, edge);
      _drawLabel(
        canvas,
        topology.nodes[id] ?? id,
        Offset(p.dx, p.dy + 14),
        isLocal ? LocalMeshColors.accent : LocalMeshColors.textSecondary,
      );
    }
  }

  Map<String, Offset> _layout(List<String> ids, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.48);
    if (ids.length == 1) return {ids.first: center};

    final result = <String, Offset>{topology.localId: center};
    final others = ids.where((id) => id != topology.localId).toList();
    final radius = math.min(size.width, size.height) * 0.34;
    for (var i = 0; i < others.length; i++) {
      final angle = (i / others.length) * 2 * math.pi - math.pi / 2;
      result[others[i]] = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * 0.78 * math.sin(angle),
      );
    }
    return result;
  }

  void _drawGrid(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = LocalMeshColors.borderMuted.withValues(alpha: 0.25)
      ..strokeWidth = 0.5;
    const step = 24.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset center, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text.length > 14 ? text.substring(0, 14) : text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontFamily: 'monospace',
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 96);
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy));
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final dir = d / len;
    var pos = 0.0;
    while (pos < len) {
      final end = math.min(pos + 6, len);
      canvas.drawLine(a + dir * pos, a + dir * end, paint);
      pos += 11;
    }
  }

  @override
  bool shouldRepaint(covariant _MeshTopologyPainter oldDelegate) =>
      oldDelegate.topology != topology;
}
