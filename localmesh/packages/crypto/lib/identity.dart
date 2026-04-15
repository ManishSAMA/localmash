import 'package:cryptography/cryptography.dart';
import 'package:domain/domain.dart';

class IdentityService implements IdentityGenerator {
  final Ed25519 _ed25519 = Ed25519();
  final X25519 _x25519 = X25519();
  final Sha256 _sha256 = Sha256();

  /// Generates a brand-new identity with fresh Ed25519 (signing) and
  /// X25519 (key exchange) key pairs. The fingerprint is the first
  /// 16 hex chars of SHA-256(ed25519_public_key).
  @override
  Future<LocalMeshIdentity> generate(String displayName) async {
    final signingKp = await _ed25519.newKeyPair();
    final encryptionKp = await _x25519.newKeyPair();

    final signingPub = await signingKp.extractPublicKey();
    final signingPriv = await signingKp.extractPrivateKeyBytes();
    final encryptionPub = await encryptionKp.extractPublicKey();
    final encryptionPriv = await encryptionKp.extractPrivateKeyBytes();

    final fingerprint = await computeFingerprint(signingPub.bytes);

    return LocalMeshIdentity(
      displayName: displayName,
      signingPublicKey: signingPub.bytes,
      signingPrivateKey: signingPriv,
      encryptionPublicKey: encryptionPub.bytes,
      encryptionPrivateKey: encryptionPriv,
      fingerprint: fingerprint,
    );
  }

  /// Computes the fingerprint for a given Ed25519 public key.
  /// Returns the first 16 hex chars of SHA-256(publicKey).
  @override
  Future<String> computeFingerprint(List<int> publicKey) async {
    final hash = await _sha256.hash(publicKey);
    final hex = hash.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return hex.substring(0, 16);
  }

  /// Reconstructs a SimpleKeyPairData from raw bytes for use with
  /// the cryptography package.
  Future<SimpleKeyPairData> reconstructSigningKeyPair(
    List<int> publicKey,
    List<int> privateKey,
  ) async {
    return SimpleKeyPairData(
      privateKey,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
  }

  Future<SimpleKeyPairData> reconstructEncryptionKeyPair(
    List<int> publicKey,
    List<int> privateKey,
  ) async {
    return SimpleKeyPairData(
      privateKey,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }
}
