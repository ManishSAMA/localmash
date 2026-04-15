import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:domain/domain.dart';

class KeyExchangeService implements SessionKeyDeriver {
  final X25519 _x25519 = X25519();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// Derives a 32-byte session key shared between two peers.
  ///
  /// Both peers MUST derive the same key when given:
  ///   - my private X25519 key
  ///   - their public X25519 key
  ///   - the same pair of fingerprints (order doesn't matter — sorted internally)
  ///
  /// Returns a 32-byte symmetric key suitable for AES-256-GCM.
  @override
  Future<List<int>> deriveSessionKey({
    required List<int> myPrivateKey,
    required List<int> theirPublicKey,
    required String myFingerprint,
    required String theirFingerprint,
  }) async {
    final myKeyPair = SimpleKeyPairData(
      myPrivateKey,
      publicKey: SimplePublicKey(
        // We don't actually need the public key for ECDH, but the API requires it.
        // Pass a zeroed placeholder of correct length.
        List<int>.filled(32, 0),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );

    final theirPub = SimplePublicKey(theirPublicKey, type: KeyPairType.x25519);

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: theirPub,
    );

    // Build a deterministic salt by sorting the two fingerprints.
    // This ensures both peers derive the SAME key regardless of who initiates.
    final sortedFps = [myFingerprint, theirFingerprint]..sort();
    final salt = utf8.encode(sortedFps.join(':'));

    final derivedKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: salt,
      info: utf8.encode('localmesh-session-v1'),
    );

    return derivedKey.extractBytes();
  }
}
