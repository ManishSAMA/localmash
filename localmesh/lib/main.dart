import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:data/data_lib.dart';
import 'di/service_locator.dart';
import 'providers/providers.dart';
import 'screens/home_screen.dart';
import 'screens/identity_setup_screen.dart';
import 'screens/permissions_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveLocalDataSource.initialize();
  final encKey = await HiveLocalDataSource.getOrCreateBoxEncryptionKey();
  await HiveLocalDataSource.openAllBoxes(identityEncryptionKey: encKey);
  await setupServiceLocator();
  runApp(const ProviderScope(child: LocalMeshApp()));
}

class LocalMeshApp extends StatelessWidget {
  const LocalMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LocalMesh',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const AppRouter(),
    );
  }
}

// Routes between the three setup steps and the main screen.
// Step 1: identity creation   → IdentitySetupScreen
// Step 2: BLE permissions     → PermissionsScreen
// Step 3: main mesh + chat    → HomeScreen (auto-starts mesh)
class AppRouter extends ConsumerStatefulWidget {
  const AppRouter({super.key});

  @override
  ConsumerState<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends ConsumerState<AppRouter> {
  // null = still checking, true/false = result
  bool? _permissionsGranted;

  static const _requiredPermissions = [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
    Permission.locationWhenInUse,
  ];

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final statuses = await Future.wait(
      _requiredPermissions.map((p) => p.status),
    );
    if (mounted) {
      setState(() => _permissionsGranted = statuses.every((s) => s.isGranted));
    }
  }

  void _onPermissionsGranted() => setState(() => _permissionsGranted = true);

  @override
  Widget build(BuildContext context) {
    final identityAsync = ref.watch(currentIdentityProvider);

    return identityAsync.when(
      loading: () => const _Splash(),
      error: (e, _) => _Splash(error: '$e'),
      data: (identity) {
        if (identity == null) return const IdentitySetupScreen();
        if (_permissionsGranted == null) return const _Splash();
        if (!_permissionsGranted!) {
          return PermissionsScreen(onPermissionsGranted: _onPermissionsGranted);
        }
        return const HomeScreen();
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({this.error});
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: error != null
            ? Text('Error: $error', style: const TextStyle(color: Colors.red))
            : const CircularProgressIndicator(),
      ),
    );
  }
}
