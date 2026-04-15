import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/providers.dart';
import 'chat_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _meshStarted = false;

  @override
  Widget build(BuildContext context) {
    final identityAsync = ref.watch(currentIdentityProvider);
    final peersAsync = ref.watch(connectedPeersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('LocalMesh')),
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
              child: ListTile(
                title: Text(id?.displayName ?? 'No identity'),
                subtitle: Text('Fingerprint: ${id?.fingerprint ?? '-'}'),
              ),
            ),
          ),
          if (!_meshStarted)
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Start Mesh'),
                onPressed: _startMesh,
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
    final granted = await _requestPermissions();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Permissions required for mesh networking')),
        );
      }
      return;
    }
    final manager = ref.read(transportManagerProvider);
    await manager.start();
    if (mounted) setState(() => _meshStarted = true);
  }

  Future<bool> _requestPermissions() async {
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ].request();
    return results.values.every((s) => s.isGranted);
  }
}
