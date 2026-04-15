import 'package:domain/domain.dart';
import '../datasources/hive_local_datasource.dart';

class HiveIdentityRepository implements IdentityRepository {
  static const String _key = 'me';

  @override
  Future<void> saveIdentity(LocalMeshIdentity identity) async {
    await HiveLocalDataSource.identityBox.put(_key, identity);
  }

  @override
  Future<LocalMeshIdentity?> getIdentity() async {
    return HiveLocalDataSource.identityBox.get(_key);
  }

  @override
  Future<bool> hasIdentity() async {
    return HiveLocalDataSource.identityBox.containsKey(_key);
  }

  @override
  Future<void> deleteIdentity() async {
    await HiveLocalDataSource.identityBox.delete(_key);
  }
}
