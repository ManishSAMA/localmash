import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/providers.dart';
import 'chat_screen.dart';
import 'identity_setup_screen.dart';
import 'network_health_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _meshStarted = false;
  bool _meshStarting = false;

  @override
  Widget build(BuildContext context) {
    final identityAsync = ref.watch(currentIdentityProvider);
    final peersAsync = ref.watch(connectedPeersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LocalMesh'),
        actions: [
          IconButton(
            icon: const Icon(Icons.network_check),
            tooltip: 'Network Health',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NetworkHealthScreen(),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          identityAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: $e'),
            ),
            data: (id) => Card(
              margin: const EdgeInsets.all(16),
              child: id == null
                  ? ListTile(
                      leading: const Icon(Icons.person_add_alt_1),
                      title: const Text('No identity yet'),
                      subtitle: const Text(
                        'Create identity first, then start mesh and chat.',
                      ),
                      trailing: FilledButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const IdentitySetupScreen(),
                          ),
                        ),
                        child: const Text('Create'),
                      ),
                    )
                  : ListTile(
                      title: Text(id.displayName),
                      subtitle: Text('Fingerprint: ${id.fingerprint}'),
                    ),
            ),
          ),
          if (!_meshStarted)
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.bluetooth_searching),
                label: Text(_meshStarting ? 'Starting Mesh...' : 'Start Mesh'),
                onPressed: identityAsync.value == null || _meshStarting
                    ? null
                    : _startMesh,
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(8),
              child: Chip(
                label: Text('Mesh active'),
                avatar: Icon(Icons.check_circle, color: Colors.green),
              ),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Connected peers',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Expanded(
            child: peersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (peers) => peers.isEmpty
                  ? const Center(child: Text('No peers connected'))
                  : ListView.builder(
                      itemCount: peers.length,
                      itemBuilder: (context, i) {
                        final p = peers[i];
                        return ListTile(
                          leading: const Icon(Icons.person),
                          title: Text(p.displayName),
                          subtitle: Text(p.id),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(peer: p),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startMesh() async {
    if (_meshStarted || _meshStarting) return;
    if (mounted) setState(() => _meshStarting = true);

    final granted = await _requestPermissions();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Permissions required for mesh networking')),
        );
      }
      if (mounted) setState(() => _meshStarting = false);
      return;
    }

    try {
      final manager = ref.read(transportManagerProvider);
      await manager.start();

      final ctrl = await ref.read(messageControllerProvider.future);
      await ctrl.start();

      if (mounted) {
        setState(() {
          _meshStarted = true;
          _meshStarting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _meshStarting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start mesh: $e')),
        );
      }
    }
  }

  Future<bool> _requestPermissions() async {
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
      // Bug 5: WifiDirectTransport requires NEARBY_WIFI_DEVICES at runtime on Android 12+;
      // without it WifiP2pManager operations throw SecurityException.
      Permission.nearbyWifiDevices,
    ].request();
    return results.values.every((s) => s.isGranted);
  }
}
