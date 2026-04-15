import 'dart:io';
import 'package:hive/hive.dart';
import 'package:data/data_lib.dart';

Future<void> setupHiveForTest() async {
  final tempDir = Directory.systemTemp.createTempSync('localmesh_test_');
  Hive.init(tempDir.path);
  HiveLocalDataSource.registerAdapters(); // NOT initialize() — no Flutter
  await HiveLocalDataSource.openAllBoxes(
    identityEncryptionKey: List<int>.filled(32, 0),
  );
}

Future<void> tearDownHive() async {
  await HiveLocalDataSource.clearAll();
  await Hive.close();
}
