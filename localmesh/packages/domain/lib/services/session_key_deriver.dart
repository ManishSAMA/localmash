// See message_signer.dart for the rationale.

abstract class SessionKeyDeriver {
  Future<List<int>> deriveSessionKey({
    required List<int> myPrivateKey,
    required List<int> theirPublicKey,
    required String myFingerprint,
    required String theirFingerprint,
  });
}
