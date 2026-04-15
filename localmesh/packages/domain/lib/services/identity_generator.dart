// See message_signer.dart for the rationale.

import '../entities/identity.dart';

abstract class IdentityGenerator {
  Future<LocalMeshIdentity> generate(String displayName);
  Future<String> computeFingerprint(List<int> signingPublicKey);
}
