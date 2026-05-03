import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domain/domain.dart';
import 'package:transport/transport.dart';
import '../controllers/message_controller.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/mesh_topology_canvas.dart';
import 'chat_screen.dart';
import 'network_health_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  _MeshState _meshState = _MeshState.idle;
  String? _meshError;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startMesh());
  }

  Future<void> _startMesh() async {
    if (_meshState == _MeshState.running) return;
    final manager = ref.read(transportManagerProvider);
    final ctrl = await ref.read(messageControllerProvider.future);
    await ctrl.start();
    if (manager.transports.isNotEmpty &&
        manager.transports.every((t) => t.state == TransportState.running)) {
      setState(() => _meshState = _MeshState.running);
      return;
    }
    setState(() {
      _meshState = _MeshState.starting;
      _meshError = null;
    });
    try {
      await manager.start();
      if (mounted) setState(() => _meshState = _MeshState.running);
    } catch (e) {
      if (mounted) {
        setState(() {
          _meshState = _MeshState.error;
          _meshError = '$e';
        });
      }
    }
  }

  _RuntimeMeshStatus _runtimeStatus(List<TransportStatus> statuses) {
    TransportStatus? ble;
    for (final status in statuses) {
      if (status.name == 'ble') {
        ble = status;
        break;
      }
    }
    if (ble?.issue == TransportIssue.bluetoothDisabled) {
      return const _RuntimeMeshStatus(
        state: _MeshState.error,
        message: 'Bluetooth disabled',
        discoveryEnabled: false,
      );
    }
    if (ble?.issue == TransportIssue.permissionDenied) {
      return const _RuntimeMeshStatus(
        state: _MeshState.error,
        message: 'Bluetooth permission denied',
        discoveryEnabled: false,
      );
    }
    if (ble?.issue == TransportIssue.locationDisabled ||
        ble?.issue == TransportIssue.unsupported ||
        ble?.issue == TransportIssue.unavailable) {
      return _RuntimeMeshStatus(
        state: _MeshState.error,
        message: ble?.message ?? 'Bluetooth unavailable',
        discoveryEnabled: false,
      );
    }
    if (statuses.any((s) => s.issue == TransportIssue.discoveryFailed)) {
      final failed = statuses.firstWhere(
        (s) => s.issue == TransportIssue.discoveryFailed,
      );
      return _RuntimeMeshStatus(
        state: _MeshState.error,
        message: failed.message ?? 'Discovery failed',
        discoveryEnabled: true,
      );
    }
    if (statuses.any((s) => s.state == TransportState.running)) {
      final peerCount = statuses.fold<int>(
        0,
        (sum, s) => sum + s.connectedPeers.length,
      );
      return _RuntimeMeshStatus(
        state: _MeshState.running,
        message: peerCount == 0 ? 'No peers nearby' : 'Peer connected',
        discoveryEnabled: true,
      );
    }
    if (statuses.any(
      (s) => s.state == TransportState.starting || s.discoveryInProgress,
    )) {
      return const _RuntimeMeshStatus(
        state: _MeshState.starting,
        message: 'Discovery in progress',
        discoveryEnabled: true,
      );
    }
    return const _RuntimeMeshStatus(
      state: _MeshState.idle,
      message: 'Mesh inactive',
      discoveryEnabled: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nearbyAsync = ref.watch(nearbyPeersProvider);
    final chatsAsync = ref.watch(connectedPeersProvider);
    final statusesAsync = ref.watch(transportStatusesProvider);
    final diagnosticsAsync = ref.watch(meshDiagnosticsProvider);
    final runtime = _runtimeStatus(statusesAsync.valueOrNull ?? const []);
    final effectiveState = runtime.state == _MeshState.idle
        ? _meshState
        : runtime.state;
    final effectiveMessage =
        runtime.message ??
        (effectiveState == _MeshState.error ? _meshError : null);
    final maxHopDepth = diagnosticsAsync.valueOrNull?.maxHopDepth ?? 0;
    final scheme = Theme.of(context).colorScheme;

    ref.listen<AsyncValue<String>>(transportErrorsProvider, (_, next) {
      next.whenData((msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mesh error: $msg'),
            backgroundColor: scheme.error,
            duration: const Duration(seconds: 6),
          ),
        );
        setState(() => _meshState = _MeshState.error);
      });
    });

    return Scaffold(
      appBar: AppBar(
        leading: Icon(Icons.router_outlined, color: scheme.primary),
        title: const Text('LOCAL_MESH'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.battery_saver,
              color: ref.watch(batterySaverProvider) ? scheme.primary : null,
            ),
            tooltip: 'Battery saver',
            onPressed: () {
              final enabled = !ref.read(batterySaverProvider);
              ref.read(batterySaverProvider.notifier).state = enabled;
              ref.read(transportManagerProvider).updateBatterySaver(enabled);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(Icons.signal_cellular_alt, color: scheme.primary),
          ),
        ],
      ),
      body: Column(
        children: [
          _MeshStatusBar(
            state: effectiveState,
            message: effectiveMessage,
            retryEnabled: runtime.discoveryEnabled,
            onRetry: _startMesh,
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _DashboardTab(
                  meshRunning: effectiveState == _MeshState.running,
                  meshStatusMessage: effectiveMessage ?? 'Mesh inactive',
                  discoveryEnabled: runtime.discoveryEnabled,
                  maxHopDepth: maxHopDepth,
                  nearbyAsync: nearbyAsync,
                  chatsAsync: chatsAsync,
                ),
                _ChatTab(chatsAsync: chatsAsync),
                const _FilesTab(),
                const NetworkHealthBody(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'DASHBOARD',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'CHAT',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_open_outlined),
            selectedIcon: Icon(Icons.folder_open),
            label: 'FILES',
          ),
          NavigationDestination(
            icon: Icon(Icons.memory_outlined),
            selectedIcon: Icon(Icons.memory),
            label: 'DIAGS',
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab({
    required this.meshRunning,
    required this.meshStatusMessage,
    required this.discoveryEnabled,
    required this.maxHopDepth,
    required this.nearbyAsync,
    required this.chatsAsync,
  });

  final bool meshRunning;
  final String meshStatusMessage;
  final bool discoveryEnabled;
  final int maxHopDepth;
  final AsyncValue<List<Peer>> nearbyAsync;
  final AsyncValue<List<Peer>> chatsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final topologyAsync = ref.watch(meshTopologyProvider);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SYS_DASHBOARD',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  'NETWORK TOPOLOGY OVERVIEW',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: LocalMeshColors.emergency,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: discoveryEnabled
                    ? () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Emergency broadcast — mesh transmit pending',
                            ),
                          ),
                        );
                      }
                    : null,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  child: Row(
                    children: [
                      Icon(Icons.campaign, color: Colors.white),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'BROADCAST EMERGENCY ALERT',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: nearbyAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (nearby) {
                final trusted = chatsAsync.valueOrNull ?? const <Peer>[];
                final actualPeerCount = nearby.length + trusted.length;
                return Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: 'ACTIVE PEERS',
                        value: '$actualPeerCount',
                        subtitle: actualPeerCount == 0
                            ? 'NO PEERS'
                            : 'CONNECTED',
                        accent: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        title: 'TOTAL HOPS REACHED',
                        value: '$maxHopDepth',
                        subtitle: 'MAX_DEPTH',
                        accent: LocalMeshColors.textSecondary,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _NetworkHealthSummary(
              status: meshRunning
                  ? (maxHopDepth > 0 ? 'ACTIVE' : 'IDLE')
                  : 'INACTIVE',
              detail: meshStatusMessage,
            ),
          ),
        ),
        if (meshRunning && discoveryEnabled) ...[
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                'RECENTLY DISCOVERED NODES',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  letterSpacing: 1,
                  color: LocalMeshColors.textSecondary,
                ),
              ),
            ),
          ),
          _NearbySliver(nearbyAsync: nearbyAsync),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TOPOLOGY',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      letterSpacing: 1.2,
                      color: LocalMeshColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  topologyAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (topology) => MeshTopologyCanvas(topology: topology),
                  ),
                ],
              ),
            ),
          ),
        ] else
          SliverFillRemaining(
            child: Center(
              child: Text(
                meshStatusMessage,
                style: const TextStyle(color: LocalMeshColors.textSecondary),
              ),
            ),
          ),
      ],
    );
  }
}

class _NetworkHealthSummary extends StatelessWidget {
  const _NetworkHealthSummary({required this.status, required this.detail});

  final String status;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.verified, color: scheme.primary, size: 36),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NETWORK HEALTH',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  status,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(
                    color: LocalMeshColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.primary),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: scheme.primary, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'SECURE',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: scheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.accent,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                letterSpacing: 0.8,
                color: LocalMeshColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NearbySliver extends ConsumerWidget {
  const _NearbySliver({required this.nearbyAsync});

  final AsyncValue<List<Peer>> nearbyAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final states =
        ref.watch(peerHandshakeStatesProvider).valueOrNull ??
        const <String, PeerHandshakeState>{};
    return nearbyAsync.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Error: $e'),
        ),
      ),
      data: (peers) {
        if (peers.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'No peers nearby — enable Bluetooth',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ),
          );
        }
        return SliverList(
          delegate: SliverChildBuilderDelegate((context, i) {
            final p = peers[i];
            final state =
                states[p.id] ??
                (p.signingPublicKey.isEmpty
                    ? PeerHandshakeState.connecting
                    : PeerHandshakeState.trustPending);
            final isProvisional =
                p.signingPublicKey.isEmpty &&
                state != PeerHandshakeState.failed;
            final isFailed = state == PeerHandshakeState.failed;
            final initials = p.displayName.isNotEmpty
                ? p.displayName[0].toUpperCase()
                : '?';
            final radio = _transportLabel(p);
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.secondaryContainer,
                  child: isProvisional
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onSecondaryContainer,
                          ),
                        )
                      : isFailed
                      ? Icon(
                          Icons.error_outline,
                          color: scheme.onSecondaryContainer,
                          size: 18,
                        )
                      : Text(
                          initials,
                          style: TextStyle(color: scheme.onSecondaryContainer),
                        ),
                ),
                title: Text(
                  p.displayName.isNotEmpty
                      ? p.displayName
                      : (p.id.length > 12 ? p.id.substring(0, 12) : p.id),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                subtitle: Text(
                  isProvisional
                      ? 'Exchanging keys…'
                      : isFailed
                      ? 'KEY EXCHANGE FAILED'
                      : 'LAST SEEN • ${_formatLastSeen(p.lastSeen)}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: radio == null
                    ? null
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: LocalMeshColors.borderMuted,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          radio,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9,
                            color: LocalMeshColors.textSecondary,
                          ),
                        ),
                      ),
                onTap: isProvisional || isFailed
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) => _FingerprintDialog(peer: p),
                      ),
              ),
            );
          }, childCount: peers.length),
        );
      },
    );
  }

  String _formatLastSeen(int lastSeenMs) {
    final d = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(lastSeenMs),
    );
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    return '${d.inHours}h';
  }

  String? _transportLabel(Peer peer) {
    if (peer.id.startsWith('lan:')) return 'LAN';
    if (peer.id.startsWith('host-')) return 'WFD';
    return null;
  }
}

class _ChatTab extends ConsumerWidget {
  const _ChatTab({required this.chatsAsync});

  final AsyncValue<List<Peer>> chatsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'ACTIVE CONVERSATIONS',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                letterSpacing: 1,
                color: LocalMeshColors.textSecondary,
              ),
            ),
          ),
        ),
        chatsAsync.when(
          loading: () => const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (e, _) => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: $e'),
            ),
          ),
          data: (peers) {
            if (peers.isEmpty) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No active chats — verify a peer from Dashboard',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              );
            }
            return SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                final p = peers[i];
                final initials = p.displayName.isNotEmpty
                    ? p.displayName[0].toUpperCase()
                    : '?';
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.primary.withValues(alpha: 0.2),
                      child: Text(
                        initials,
                        style: TextStyle(color: scheme.primary),
                      ),
                    ),
                    title: Text(
                      p.displayName.isNotEmpty
                          ? p.displayName
                          : p.id.substring(0, 12),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    subtitle: Text(
                      p.id,
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ChatScreen(peer: p)),
                    ),
                  ),
                );
              }, childCount: peers.length),
            );
          },
        ),
      ],
    );
  }
}

class _FilesTab extends StatelessWidget {
  const _FilesTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'SECURE FILE TRANSFER',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'End-to-end encrypted chunks over the mesh — coming soon.',
              textAlign: TextAlign.center,
              style: TextStyle(color: LocalMeshColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _FingerprintDialog extends ConsumerStatefulWidget {
  const _FingerprintDialog({required this.peer});
  final Peer peer;

  @override
  ConsumerState<_FingerprintDialog> createState() => _FingerprintDialogState();
}

class _FingerprintDialogState extends ConsumerState<_FingerprintDialog> {
  bool _loading = false;

  String _formatFingerprint(List<int> key) {
    final hex = key
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
    final groups = <String>[];
    for (var i = 0; i < hex.length; i += 4) {
      groups.add(hex.substring(i, i + 4 < hex.length ? i + 4 : hex.length));
    }
    final lines = <String>[];
    for (var i = 0; i < groups.length; i += 8) {
      lines.add(
        groups
            .sublist(i, i + 8 < groups.length ? i + 8 : groups.length)
            .join(' '),
      );
    }
    return lines.join('\n');
  }

  Future<void> _verify() async {
    setState(() => _loading = true);
    final ctrl = ref.read(messageControllerSyncProvider);
    await ctrl.trustPeer(widget.peer.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(peer: widget.peer.copyWith(isTrusted: true)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = widget.peer.displayName.isNotEmpty
        ? widget.peer.displayName
        : widget.peer.id.substring(0, 12);

    return AlertDialog(
      backgroundColor: LocalMeshColors.surfaceCard,
      title: Text(
        'CONNECT TO $name?',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Verify fingerprint matches their device:',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: LocalMeshColors.borderMuted),
            ),
            child: Text(
              _formatFingerprint(widget.peer.signingPublicKey),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _loading ? null : _verify,
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.verified_user, size: 18),
          label: const Text('Verify & Chat'),
        ),
      ],
    );
  }
}

enum _MeshState { idle, starting, running, error }

class _RuntimeMeshStatus {
  const _RuntimeMeshStatus({
    required this.state,
    required this.discoveryEnabled,
    this.message,
  });

  final _MeshState state;
  final String? message;
  final bool discoveryEnabled;
}

class _MeshStatusBar extends StatelessWidget {
  const _MeshStatusBar({
    required this.state,
    required this.message,
    required this.retryEnabled,
    required this.onRetry,
  });

  final _MeshState state;
  final String? message;
  final bool retryEnabled;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return switch (state) {
      _MeshState.idle => const SizedBox.shrink(),
      _MeshState.starting => Container(
        width: double.infinity,
        color: LocalMeshColors.surfaceCard,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              (message ?? 'Starting mesh').toUpperCase(),
              style: TextStyle(
                fontFamily: 'monospace',
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      _MeshState.running => Container(
        width: double.infinity,
        color: LocalMeshColors.surfaceCard,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.wifi_tethering, color: scheme.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              (message ?? 'Mesh active').toUpperCase(),
              style: TextStyle(
                fontFamily: 'monospace',
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      _MeshState.error => Container(
        width: double.infinity,
        color: scheme.errorContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message ?? 'Failed to start mesh',
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: retryEnabled ? onRetry : null,
              child: Text(
                'Retry',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    };
  }
}
