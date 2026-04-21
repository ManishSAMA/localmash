import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domain/domain.dart';
import '../providers/providers.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.peer});

  final Peer peer;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(chatMessagesProvider(widget.peer.id));
    final messageController = ref.watch(messageControllerSyncProvider);

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
      appBar: AppBar(title: Text(widget.peer.displayName)),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (messages) => messages.isEmpty
                  ? const Center(child: Text('No messages yet'))
                  : ListView.builder(
                      reverse: true,
                      itemCount: messages.length,
                      itemBuilder: (context, i) {
                        final m = messages[messages.length - 1 - i];
                        final plaintext = messageController.cachedPlaintextFor(m.id);
                        return ListTile(
                          title: Text(plaintext ?? '[message not yet decrypted]'),
                          subtitle: Text(
                            '${m.senderId.substring(0, 8)}  •  '
                            '${DateTime.fromMillisecondsSinceEpoch(m.createdAt).toLocal()}',
                          ),
                        );
                      },
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Type a message',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  onPressed: _sending ? null : _send,
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
