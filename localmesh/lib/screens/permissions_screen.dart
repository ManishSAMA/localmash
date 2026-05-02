import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key, required this.onPermissionsGranted});
  final VoidCallback onPermissionsGranted;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _requesting = false;
  bool _permanentlyDenied = false;

  static const _blePermissions = [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
    Permission.locationWhenInUse,
  ];

  Future<void> _requestPermissions() async {
    setState(() {
      _requesting = true;
      _permanentlyDenied = false;
    });

    final results = await _blePermissions.request();
    final allGranted = results.values.every((s) => s.isGranted);
    final anyPermanentlyDenied =
        results.values.any((s) => s.isPermanentlyDenied);

    if (!mounted) return;

    if (allGranted) {
      // Also request nearby wifi devices — optional, doesn't block
      await Permission.nearbyWifiDevices.request();
      widget.onPermissionsGranted();
    } else {
      setState(() {
        _requesting = false;
        _permanentlyDenied = anyPermanentlyDenied;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.bluetooth_searching,
                  size: 72, color: scheme.primary),
              const SizedBox(height: 32),
              Text(
                'Permissions needed',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'LocalMesh uses Bluetooth to discover and connect with nearby devices — no internet required.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 40),
              const _PermissionRow(
                icon: Icons.bluetooth,
                label: 'Bluetooth scan & connect',
                description: 'Discover nearby LocalMesh devices',
              ),
              const SizedBox(height: 16),
              const _PermissionRow(
                icon: Icons.location_on_outlined,
                label: 'Location',
                description: 'Required by Android for BLE scanning',
              ),
              const Spacer(),
              if (_permanentlyDenied) ...[
                Text(
                  'Some permissions were permanently denied. Open Settings to grant them.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.error),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Open Settings'),
                  onPressed: openAppSettings,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _requesting ? null : _requestPermissions,
                  child: const Text('Try again'),
                ),
              ] else
                FilledButton.icon(
                  icon: _requesting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_requesting ? 'Requesting…' : 'Grant permissions'),
                  onPressed: _requesting ? null : _requestPermissions,
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.label,
    required this.description,
  });

  final IconData icon;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(description,
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
