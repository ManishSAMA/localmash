import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:domain/domain.dart';
import '../theme/app_theme.dart';

/// Dark map-style mesh view: nodes + active (green) / inactive (dashed) links.
class MeshTopologyCanvas extends StatelessWidget {
  const MeshTopologyCanvas({
    super.key,
    required this.peers,
    this.minHeight = 220,
  });

  final List<Peer> peers;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = math.max(minHeight, 200.0);
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CustomPaint(
            size: Size(w, h),
            painter: _MeshTopologyPainter(
              peerCount: peers.isEmpty ? 5 : peers.length,
            ),
            child: SizedBox(width: w, height: h),
          ),
        );
      },
    );
  }
}

class _MeshTopologyPainter extends CustomPainter {
  _MeshTopologyPainter({required this.peerCount});

  final int peerCount;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = LocalMeshColors.background;
    canvas.drawRect(Offset.zero & size, bg);

    // Map-like desaturated wash (reference: dark map under mesh)
    final wash = Paint()
      ..color = const Color(0xFF1c2838).withValues(alpha: 0.55);
    canvas.drawRect(Offset.zero & size, wash);

    // Faint area labels (decorative — matches reference map overlay)
    void drawPlace(String text, Offset at, double opacity) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: opacity),
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at);
    }

    drawPlace('Mississauga', Offset(size.width * 0.08, size.height * 0.12), 0.07);
    drawPlace('Brampton', Offset(size.width * 0.58, size.height * 0.78), 0.06);

    // Faint grid
    final grid = Paint()
      ..color = LocalMeshColors.borderMuted.withValues(alpha: 0.35)
      ..strokeWidth = 0.5;
    const step = 24.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final n = math.max(3, math.min(peerCount, 8));
    final center = Offset(size.width * 0.5, size.height * 0.48);
    final radius = math.min(size.width, size.height) * 0.32;
    final nodes = <Offset>[];
    for (var i = 0; i < n; i++) {
      final t = (i / n) * 2 * math.pi - math.pi / 2;
      nodes.add(Offset(
        center.dx + radius * 0.85 * math.cos(t),
        center.dy + radius * 0.75 * math.sin(t),
      ));
    }

    // Inactive / potential links (dashed grey)
    final dash = Paint()
      ..color = LocalMeshColors.textSecondary.withValues(alpha: 0.45)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        if ((i - j).abs() == 1 || (i == 0 && j == n - 1)) continue;
        _drawDashedLine(canvas, nodes[i], nodes[j], dash, 5, 4);
      }
    }

    // Active mesh links (Y / ring subset)
    final active = Paint()
      ..color = LocalMeshColors.accent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      if (i < 3) {
        canvas.drawLine(nodes[i], nodes[j], active);
      }
    }
    canvas.drawLine(nodes[0], center, active);

    // Nodes
    final nodeFill = Paint()..color = LocalMeshColors.surfaceCard;
    final nodeEdge = Paint()
      ..color = LocalMeshColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final p in nodes) {
      canvas.drawCircle(p, 6, nodeFill);
      canvas.drawCircle(p, 6, nodeEdge);
    }
    canvas.drawCircle(center, 7, nodeFill);
    canvas.drawCircle(center, 7, nodeEdge..strokeWidth = 2);

    final tp = TextPainter(
      text: TextSpan(
        text: 'TOPOLOGY ACTIVE',
        style: TextStyle(
          color: LocalMeshColors.accent.withValues(alpha: 0.9),
          fontSize: 11,
          fontFamily: 'monospace',
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy + 18));
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint,
    double dash,
    double gap,
  ) {
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final dir = d / len;
    var pos = 0.0;
    while (pos < len) {
      final p0 = a + dir * pos;
      final seg = math.min(dash, len - pos);
      final p1 = a + dir * (pos + seg);
      canvas.drawLine(p0, p1, paint);
      pos += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _MeshTopologyPainter oldDelegate) =>
      oldDelegate.peerCount != peerCount;
}
