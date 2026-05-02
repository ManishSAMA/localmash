import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domain/domain.dart';
import 'package:transport/transport.dart';
import '../providers/providers.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startMesh());
  }

  Future<void> _startMesh() async {
    if (_meshState == _MeshState.running) return;
    final manager = ref.read(transportManagerProvider);
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
      final ctrl = await ref.read(messageControllerProvider.future);
      await ctrl.start();
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

  @override
  Widget build(BuildContext context) {
    final nearbyAsync = ref.watch(nearbyPeersProvider);
    final chatsAsync = ref.watch(connectedPeersProvider);
    final scheme = Theme.of(context).colorScheme;

    ref.listen<AsyncValue<String>>(transportErrorsProvider, (_, next) {
      next.whenData((msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Mesh error: $msg'),
          backgroundColor: scheme.error,
          duration: const Duration(seconds: 6),
        ));
        setState(() => _meshState = _MeshState.error);
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('LocalMesh'),
        actions: [
          IconButton(
            icon: const Icon(Icons.network_check),
            tooltip: 'Network health',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NetworkHealthScreen()),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                _MeshStatusBar(
                  state: _meshState,
                  error: _meshError,
                  onRetry: _startMesh,
                ),
                const Divider(height: 1),
              ],
            ),
          ),
          if (_meshState == _MeshState.running) ...[
            const _SectionHeader(title: 'Nearby'),
            _NearbySection(nearbyAsync: nearbyAsync),
            const _SectionHeader(title: 'Chats'),
            _ChatsSection(chatsAsync: chatsAsync),
          ] else
            SliverFillRemaining(
              child: Center(
                child: Text(
                  _meshState == _MeshState.starting
                      ? 'Starting mesh…'
                      : 'Start the mesh to discover peers',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _NearbySection extends ConsumerWidget {
  const _NearbySection({required this.nearbyAsync});
  final AsyncValue<List<Peer>> nearbyAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
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
      data: (peers) => peers.isEmpty
          ? SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'No peers nearby — make sure Bluetooth is on',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
            )
          : SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final p = peers[i];
                  final isProvisional = p.signingPublicKey.isEmpty;
                  final initials = p.displayName.isNotEmpty
                      ? p.displayName[0].toUpperCase()
                      : '?';
                  return ListTile(
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
                          : Text(initials,
                              style: TextStyle(
                                  color: scheme.onSecondaryContainer)),
                    ),
                    title: Text(p.displayName.isNotEmpty
                        ? p.displayName
                        : p.id.length > 12
                            ? p.id.substring(0, 12)
                            : p.id),
                    subtitle: Text(
                      isProvisional
                          ? 'Exchanging keys…'
                          : 'Tap to verify & connect',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: isProvisional
                        ? null
                        : const Icon(Icons.verified_user_outlined, size: 18),
                    onTap: isProvisional
                        ? null
                        : () => showDialog<void>(
                              context: context,
                              builder: (_) => _FingerprintDialog(peer: p),
                            ),
                  );
                },
                childCount: peers.length,
              ),
            ),
    );
  }
}

class _ChatsSection extends ConsumerWidget {
  const _ChatsSection({required this.chatsAsync});
  final AsyncValue<List<Peer>> chatsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return chatsAsync.when(
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
      data: (peers) => peers.isEmpty
          ? SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'No active chats',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
            )
          : SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final p = peers[i];
                  final initials = p.displayName.isNotEmpty
                      ? p.displayName[0].toUpperCase()
                      : '?';
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.primaryContainer,
                      child: Text(initials,
                          style:
                              TextStyle(color: scheme.onPrimaryContainer)),
                    ),
                    title: Text(p.displayName.isNotEmpty
                        ? p.displayName
                        : p.id.substring(0, 12)),
                    subtitle: Text(
                      p.id,
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => ChatScreen(peer: p)),
                    ),
                  );
                },
                childCount: peers.length,
              ),
            ),
    );
  }
}

class _FingerprintDialog extends ConsumerStatefulWidget {
  const _FingerprintDialog({required this.peer});
  final Peer peer;

  @override
  ConsumerState<_FingerprintDialog> createState() =>
      _FingerprintDialogState();
}

class _FingerprintDialogState extends ConsumerState<_FingerprintDialog> {
  bool _loading = false;

  String _formatFingerprint(List<int> key) {
    final hex = key
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
    // group into blocks of 4 chars, 8 per line
    final groups = <String>[];
    for (var i = 0; i < hex.length; i += 4) {
      groups.add(hex.substring(i, i + 4 < hex.length ? i + 4 : hex.length));
    }
    final lines = <String>[];
    for (var i = 0; i < groups.length; i += 8) {
      lines.add(groups
          .sublist(i, i + 8 < groups.length ? i + 8 : groups.length)
          .join(' '));
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
      title: Text('Connect to $name?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Verify their identity fingerprint matches what you see on their device:',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
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

class _MeshStatusBar extends StatelessWidget {
  const _MeshStatusBar({
    required this.state,
    required this.error,
    required this.onRetry,
  });

  final _MeshState state;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return switch (state) {
      _MeshState.idle => const SizedBox.shrink(),
      _MeshState.starting => Container(
          color: scheme.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: const Row(children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Starting mesh…'),
          ]),
        ),
      _MeshState.running => Container(
          color: Colors.green.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(Icons.wifi_tethering, color: Colors.green.shade700, size: 18),
            const SizedBox(width: 8),
            Text('Mesh active',
                style: TextStyle(color: Colors.green.shade800)),
          ]),
        ),
      _MeshState.error => Container(
          color: scheme.errorContainer,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error ?? 'Failed to start mesh',
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text('Retry',
                  style: TextStyle(color: scheme.onErrorContainer)),
            ),
          ]),
        ),
    };
  }
}
