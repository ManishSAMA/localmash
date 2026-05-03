import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';

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
      appBar: AppBar(
        leading: Icon(Icons.router_outlined, color: scheme.primary),
        title: const Text('LOCAL_MESH'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                'RADIO PERMISSIONS',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'SYS_SCAN_ACCESS',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Bluetooth Low Energy discovers mesh peers; no cloud. '
                'Android requires location for BLE scan on many devices.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: LocalMeshColors.textSecondary,
                      height: 1.45,
                    ),
              ),
              const SizedBox(height: 28),
              Icon(
                Icons.bluetooth_searching,
                size: 56,
                color: scheme.primary,
              ),
              const SizedBox(height: 28),
              const _PermissionRow(
                icon: Icons.bluetooth,
                label: 'BLUETOOTH SCAN & CONNECT',
                description: 'Discover and link nearby nodes',
              ),
              const SizedBox(height: 14),
              const _PermissionRow(
                icon: Icons.location_on_outlined,
                label: 'LOCATION (WHILE IN USE)',
                description: 'Required by OS for BLE scanning',
              ),
              const Spacer(),
              if (_permanentlyDenied) ...[
                Text(
                  'Permissions blocked — open Settings to enable.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.error,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('OPEN SETTINGS'),
                  onPressed: openAppSettings,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _requesting ? null : _requestPermissions,
                  child: const Text('TRY AGAIN'),
                ),
              ] else
                FilledButton.icon(
                  key: const ValueKey('grant_permissions'),
                  icon: _requesting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF0D1117),
                          ),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(
                    _requesting ? 'REQUESTING…' : 'GRANT PERMISSIONS',
                  ),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LocalMeshColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: LocalMeshColors.borderMuted),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: LocalMeshColors.borderMuted),
            ),
            child: Icon(icon, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    fontSize: 11,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
