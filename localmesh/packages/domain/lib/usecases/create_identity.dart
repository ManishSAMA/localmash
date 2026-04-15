import '../entities/identity.dart';
import '../repositories/identity_repository.dart';
import '../services/identity_generator.dart';

class CreateIdentity {
  CreateIdentity({
    required IdentityGenerator generator,
    required IdentityRepository repository,
  })  : _generator = generator,
        _repository = repository;

  final IdentityGenerator _generator;
  final IdentityRepository _repository;

  /// Generates a new identity and persists it.
  /// Throws StateError if an identity already exists (call deleteIdentity first).
  Future<LocalMeshIdentity> call(String displayName) async {
    if (await _repository.hasIdentity()) {
      throw StateError('Identity already exists. Delete it first.');
    }
    final identity = await _generator.generate(displayName);
    await _repository.saveIdentity(identity);
    return identity;
  }
}
