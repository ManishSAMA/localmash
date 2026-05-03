import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domain/domain.dart';
import 'package:transport/transport_package.dart';
import '../app_start.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/diagnostics_panels.dart';
import '../widgets/mesh_topology_canvas.dart';

final allPeersProvider = FutureProvider<List<Peer>>(
  (ref) async {
    ref.watch(peerEventsProvider);
    ref.watch(transportStatusesProvider);
    ref.watch(peerRepositoryRevisionProvider);
    return ref.read(peerRepoProvider).getConnectedPeers();
  },
);

class NetworkHealthScreen extends ConsumerWidget {
  const NetworkHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Icons.router_outlined),
        title: const Text('LOCAL_MESH'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.signal_cellular_alt, size: 22),
          ),
        ],
      ),
      body: const NetworkHealthBody(),
    );
  }
}

class NetworkHealthBody extends ConsumerWidget {
  const NetworkHealthBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(transportManagerProvider);
    final peersAsync = ref.watch(allPeersProvider);
    final diagnosticsAsync = ref.watch(meshDiagnosticsProvider);
    ref.watch(transportStatusesProvider);
    ref.watch(peerEventsProvider);
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _DiagnosticsHeaderCard(),
        const SizedBox(height: 16),
        const LatencyPerHopPanel(samples: []),
        const SizedBox(height: 12),
        const BatteryDrainPanel(),
        const SizedBox(height: 12),
        diagnosticsAsync.when(
          loading: () => const RoutingEventsLogPanel(events: []),
          error: (_, __) => const RoutingEventsLogPanel(events: []),
          data: (diagnostics) =>
              RoutingEventsLogPanel(events: diagnostics.routingEvents),
        ),
        const SizedBox(height: 20),
        const _SectionLabel('MESH TOPOLOGY'),
        const SizedBox(height: 8),
        peersAsync.when(
          loading: () => const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Error: $e'),
          data: (peers) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.hub_outlined, color: scheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      peers.isEmpty
                          ? 'MESH INACTIVE // 0 PEERS'
                          : 'MESH ACTIVE // ${peers.length} PEERS',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: scheme.primary,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                MeshTopologyCanvas(peers: peers, minHeight: 200),
                const SizedBox(height: 6),
                const Text(
                  'SCANNING FREQUENCY: 2.4GHZ • BLE / WFD / LAN',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: LocalMeshColors.textSecondary,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        const _SectionLabel('TRANSPORTS'),
        ...manager.transports.map((t) => _TransportTile(transport: t)),
        const SizedBox(height: 24),
        const _SectionLabel('CONNECTED PEERS'),
        peersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
          data: (peers) {
            if (peers.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'NO PEERS CONNECTED',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: LocalMeshColors.textSecondary,
                  ),
                ),
              );
            }
            return Column(
              children: peers.map((p) => _PeerTile(peer: p)).toList(),
            );
          },
        ),
        const SizedBox(height: 24),
        const _SectionLabel('MESSAGE STATS'),
        const _MessageStats(),
      ],
    );
  }
}

class _DiagnosticsHeaderCard extends ConsumerStatefulWidget {
  const _DiagnosticsHeaderCard();

  @override
  ConsumerState<_DiagnosticsHeaderCard> createState() =>
      _DiagnosticsHeaderCardState();
}

class _DiagnosticsHeaderCardState extends ConsumerState<_DiagnosticsHeaderCard> {
  Timer? _uptimeTimer;

  @override
  void initState() {
    super.initState();
    _uptimeTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _uptimeTimer?.cancel();
    super.dispose();
  }

  String _uptimeLine() {
    final start = localMeshAppStartedAt;
    if (start == null) return 'SYS_UPTIME: —';
    final d = DateTime.now().difference(start);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return 'SYS_UPTIME: ${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final batteryOn = ref.watch(batterySaverProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi_tethering, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'DIAGNOSTICS_ACTIVE',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _uptimeLine(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'BATT_SAVER_SCAN',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Switch(
                  value: batteryOn,
                  onChanged: (v) {
                    ref.read(batterySaverProvider.notifier).state = v;
                    ref.read(transportManagerProvider).updateBatterySaver(v);
                  },
                  activeThumbColor: scheme.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          letterSpacing: 1.2,
          color: LocalMeshColors.textSecondary,
        ),
      );
}

class _TransportTile extends StatelessWidget {
  const _TransportTile({required this.transport});

  final Transport transport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRunning = transport.state == TransportState.running;
    final color = isRunning ? scheme.primary : LocalMeshColors.textSecondary;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.radio_button_checked, color: color),
        title: Text(
          transport.name.toUpperCase(),
          style: const TextStyle(fontFamily: 'monospace', letterSpacing: 0.6),
        ),
        subtitle: Text(
          'STATE: ${transport.state.name.toUpperCase()}',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
          ),
        ),
        trailing: Chip(
          label: Text(
            '${transport.connectedPeers.length} PEERS',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
          ),
          side: const BorderSide(color: LocalMeshColors.borderMuted),
          backgroundColor: LocalMeshColors.surfaceCard,
        ),
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.peer});

  final Peer peer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.memory, color: scheme.primary),
        title: Text(
          peer.displayName.isNotEmpty ? peer.displayName : peer.id,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        subtitle: Text(
          '${peer.id} • ${peer.isTrusted ? "TRUSTED" : "NEW"}',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          peer.isConnected ? Icons.link : Icons.link_off,
          color: peer.isConnected ? scheme.primary : LocalMeshColors.textSecondary,
        ),
      ),
    );
  }
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
            leading: Icon(Icons.message_outlined,
                color: Theme.of(context).colorScheme.primary),
            title: const Text(
              'MESSAGES STORED',
              style: TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
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
