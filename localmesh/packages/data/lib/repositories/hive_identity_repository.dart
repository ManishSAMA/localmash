import 'package:domain/domain.dart';

class HiveIdentityRepository implements IdentityRepository {
  @override
  Future<void> saveIdentity(LocalMeshIdentity identity) {
    throw UnimplementedError();
  }

  @override
  Future<LocalMeshIdentity?> getIdentity() {
    throw UnimplementedError();
  }

  @override
  Future<bool> hasIdentity() {
    throw UnimplementedError();
  }
}
