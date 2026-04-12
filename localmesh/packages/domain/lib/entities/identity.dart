class KeyPair {
  const KeyPair({
    required this.publicKey,
    required this.privateKey,
  });

  final List<int> publicKey;
  final List<int> privateKey;
}

class LocalMeshIdentity {
  const LocalMeshIdentity({
    required this.displayName,
    required this.signingKeyPair,
    required this.encryptionKeyPair,
    required this.fingerprint,
  });

  final String displayName;
  final KeyPair signingKeyPair;
  final KeyPair encryptionKeyPair;
  final String fingerprint;
}
