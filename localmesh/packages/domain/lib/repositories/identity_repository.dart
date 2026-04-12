import '../entities/identity.dart';

abstract class IdentityRepository {
  Future<void> saveIdentity(LocalMeshIdentity identity);
  Future<LocalMeshIdentity?> getIdentity();
  Future<bool> hasIdentity();
}
