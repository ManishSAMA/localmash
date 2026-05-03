import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domain/domain.dart';
import '../controllers/message_controller.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_message_row.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.peer});

  final Peer peer;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final Map<String, Future<String?>> _decryptFutures = {};
  bool _sending = false;

  Future<String?> _decryptFuture(LocalMeshMessage msg, MessageController ctrl) {
    return _decryptFutures.putIfAbsent(
      msg.id,
      () => ctrl.decryptForDisplay(msg),
    );
  }

  @override
  void dispose() {
    _decryptFutures.clear();
    _controller.dispose();
    super.dispose();
  }

  String _formatZulu(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return "$h:${m}Z";
  }

  String _nodeLabel(Peer p) {
    final raw = p.displayName.isNotEmpty
        ? p.displayName
        : (p.id.length > 8 ? p.id.substring(0, 8) : p.id);
    return 'NODE_${raw.replaceAll(' ', '_').toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(chatMessagesProvider(widget.peer.id));
    final messageController = ref.watch(messageControllerSyncProvider);
    final identityAsync = ref.watch(currentIdentityProvider);
    final scheme = Theme.of(context).colorScheme;

    ref.listen(decryptedMessagesProvider, (_, next) {
      next.whenData((dm) {
        final isForThisChat = dm.envelope.senderId == widget.peer.id ||
            dm.envelope.recipientId == widget.peer.id;
        if (isForThisChat && mounted) {
          ref.invalidate(chatMessagesProvider(widget.peer.id));
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _nodeLabel(widget.peer),
          style: const TextStyle(fontFamily: 'monospace', letterSpacing: 0.5),
        ),
        actions: [
          Icon(Icons.signal_cellular_alt, color: scheme.primary, size: 20),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: LocalMeshColors.surfaceCard,
              border: Border(
                bottom: BorderSide(color: LocalMeshColors.borderMuted),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: scheme.primary, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'AES-256 E2EE ACTIVE',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      letterSpacing: 0.6,
                      color: LocalMeshColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Divider(
                    height: 1,
                    color: LocalMeshColors.borderMuted,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'T-MINUS 12:00:00',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      letterSpacing: 1.2,
                      color: LocalMeshColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(
                    height: 1,
                    color: LocalMeshColors.borderMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: identityAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (identity) => messagesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (messages) => messages.isEmpty
                    ? Center(
                        child: Text(
                          'NO MESSAGES — MESH IDLE',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                            letterSpacing: 1,
                          ),
                        ),
                      )
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.only(bottom: 12, top: 8),
                        itemCount: messages.length,
                        itemBuilder: (context, i) {
                          final m = messages[messages.length - 1 - i];
                          final myFp = identity?.fingerprint ?? '';
                          final isMine = m.senderId == myFp;
                          final cached =
                              messageController.cachedPlaintextFor(m.id);
                          if (cached != null) {
                            return ChatMessageRow(
                              isMine: isMine,
                              plaintext: cached,
                              timeLabel: _formatZulu(m.createdAt),
                              senderLabel:
                                  isMine ? null : _nodeLabel(widget.peer),
                              hopCount: m.hopCount,
                            );
                          }
                          return FutureBuilder<String?>(
                            future: _decryptFuture(m, messageController),
                            builder: (context, snap) => ChatMessageRow(
                              isMine: isMine,
                              plaintext: snap.data ?? '[DECRYPTING…]',
                              timeLabel: _formatZulu(m.createdAt),
                              senderLabel:
                                  isMine ? null : _nodeLabel(widget.peer),
                              hopCount: m.hopCount,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Material(
                  color: LocalMeshColors.surfaceCard,
                  borderRadius: BorderRadius.circular(8),
                  child: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.add, color: LocalMeshColors.textSecondary),
                    tooltip: 'Attachments',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'TRANSMIT MESSAGE…',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: LocalMeshColors.accent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: _sending ? null : _send,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _sending
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF0D1117),
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Color(0xFF0D1117),
                              size: 22,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    if (_controller.text.trim().isEmpty) return;
    setState(() => _sending = true);
    final text = _controller.text.trim();
    try {
      final ctrl = ref.read(messageControllerSyncProvider);
      await ctrl.sendText(
        recipientId: widget.peer.id,
        plaintext: text,
      );
      _controller.clear();
      ref.invalidate(chatMessagesProvider(widget.peer.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
