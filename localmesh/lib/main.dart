import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data/data_lib.dart';
import 'di/service_locator.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive and open all boxes BEFORE runApp
  await HiveLocalDataSource.initialize();
  final encKey = await HiveLocalDataSource.getOrCreateBoxEncryptionKey();
  await HiveLocalDataSource.openAllBoxes(identityEncryptionKey: encKey);

  // Wire DI
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
      home: const HomeScreen(),
    );
  }
}
