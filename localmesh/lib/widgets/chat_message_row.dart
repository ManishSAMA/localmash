import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Tactical chat row: mine = right / neon green; theirs = left / grey panel.
class ChatMessageRow extends StatelessWidget {
  const ChatMessageRow({
    super.key,
    required this.isMine,
    required this.plaintext,
    required this.timeLabel,
    this.senderLabel,
    this.hopCount = 0,
    this.showRelayIcons = true,
  });

  final bool isMine;
  final String plaintext;
  final String timeLabel;
  final String? senderLabel;
  final int hopCount;
  final bool showRelayIcons;

  @override
  Widget build(BuildContext context) {
    final bubble = isMine ? _buildMine(context) : _buildTheirs(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: bubble,
      ),
    );
  }

  Widget _buildMine(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: LocalMeshColors.accent,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(10),
              topRight: Radius.circular(10),
              bottomLeft: Radius.circular(10),
              bottomRight: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: LocalMeshColors.accent.withValues(alpha: 0.12),
                blurRadius: 8,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              plaintext,
              style: const TextStyle(
                color: Color(0xFF0D1117),
                fontSize: 15,
                height: 1.35,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              timeLabel,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: LocalMeshColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            if (showRelayIcons) ...[
              Icon(
                hopCount > 0 ? Icons.sync_alt : Icons.done_all,
                size: 15,
                color: hopCount > 0
                    ? LocalMeshColors.textSecondary
                    : LocalMeshColors.accent,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildTheirs(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (senderLabel != null) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                senderLabel!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              if (hopCount == 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: LocalMeshColors.accent, width: 1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'DIRECT',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9,
                      color: LocalMeshColors.accent,
                      letterSpacing: 0.5,
                    ),
                  ),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: LocalMeshColors.surfaceCard,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: LocalMeshColors.borderMuted),
                  ),
                  child: Text(
                    'VIA $hopCount HOPS',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9,
                      color: LocalMeshColors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            color: LocalMeshColors.bubbleTheirs,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(10),
              bottomRight: Radius.circular(10),
              bottomLeft: Radius.circular(10),
            ),
            border: Border.all(color: LocalMeshColors.borderMuted),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              plaintext,
              style: const TextStyle(
                color: Color(0xFFE6EDF3),
                fontSize: 15,
                height: 1.35,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          timeLabel,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: LocalMeshColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
