import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domain/domain.dart';
import 'package:transport/transport_package.dart';
import '../providers/providers.dart';

class NetworkHealthScreen extends ConsumerWidget {
  const NetworkHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(transportManagerProvider);
    final peersAsync = ref.watch(connectedPeersProvider);
    // Re-render whenever a peer event fires
    ref.watch(peerEventsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Network Health')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader(title: 'Transports'),
          ...manager.transports.map((t) => _TransportTile(transport: t)),
          const SizedBox(height: 24),
          const _SectionHeader(title: 'Connected Peers'),
          peersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (peers) {
              if (peers.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No peers connected'),
                );
              }
              return Column(
                children: peers.map((p) => _PeerTile(peer: p)).toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          const _SectionHeader(title: 'Message Stats'),
          const _MessageStats(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      );
}

class _TransportTile extends StatelessWidget {
  const _TransportTile({required this.transport});

  final Transport transport;

  @override
  Widget build(BuildContext context) {
    final isRunning = transport.state == TransportState.running;
    final color = isRunning ? Colors.green : Colors.grey;
    return Card(
      child: ListTile(
        leading: Icon(Icons.radio_button_checked, color: color),
        title: Text(transport.name.toUpperCase()),
        subtitle: Text('State: ${transport.state.name}'),
        trailing: Chip(
            label: Text('${transport.connectedPeers.length} peers')),
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.peer});

  final Peer peer;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const Icon(Icons.person),
          title: Text(peer.displayName),
          subtitle:
              Text('${peer.id} • ${peer.isTrusted ? "trusted" : "new"}'),
          trailing: Icon(
            peer.isConnected ? Icons.link : Icons.link_off,
            color: peer.isConnected ? Colors.green : Colors.grey,
          ),
        ),
      );
}

class _MessageStats extends ConsumerWidget {
  const _MessageStats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(incomingDataProvider);
    final msgRepo = ref.read(messageRepoProvider);

    return FutureBuilder<int>(
      future: _countAllMessages(msgRepo),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return Card(
          child: ListTile(
            leading: const Icon(Icons.message),
            title: const Text('Messages stored'),
            trailing: Text(
              '${snap.data}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        );
      },
    );
  }

  Future<int> _countAllMessages(MessageRepository repo) async {
    final all = await repo.getMessagesForChat('*', limit: 10000);
    return all.length;
  }
}
