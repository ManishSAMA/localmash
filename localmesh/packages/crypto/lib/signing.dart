import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:domain/domain.dart';

class SigningService {
  final Ed25519 _ed25519 = Ed25519();

  /// Builds the canonical byte sequence that gets signed.
  /// Both signer and verifier MUST produce identical bytes.
  /// Format: id || senderId || payload || ttl(4 bytes BE) || lamportTs(8 bytes BE)
  Uint8List _buildSigningInput(LocalMeshMessage msg) {
    final builder = BytesBuilder();
    builder.add(utf8.encode(msg.id));
    builder.add(utf8.encode(msg.senderId));
    builder.add(msg.payload);

    final ttlBytes = ByteData(4)..setUint32(0, msg.ttl, Endian.big);
    builder.add(ttlBytes.buffer.asUint8List());

    final tsBytes = ByteData(8)..setInt64(0, msg.lamportTs, Endian.big);
    builder.add(tsBytes.buffer.asUint8List());

    return builder.toBytes();
  }

  /// Signs a message with the sender's Ed25519 private key.
  /// Returns the signature bytes (typically 64 bytes for Ed25519).
  Future<List<int>> signMessage({
    required LocalMeshMessage message,
    required List<int> signingPrivateKey,
    required List<int> signingPublicKey,
  }) async {
    final input = _buildSigningInput(message);

    final keyPair = SimpleKeyPairData(
      signingPrivateKey,
      publicKey: SimplePublicKey(signingPublicKey, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );

    final signature = await _ed25519.sign(input, keyPair: keyPair);
    return signature.bytes;
  }

  /// Verifies a message's signature against the sender's public key.
  /// Returns true if valid, false otherwise. Never throws on bad signatures.
  Future<bool> verifyMessage({
    required LocalMeshMessage message,
    required List<int> signingPublicKey,
  }) async {
    try {
      final input = _buildSigningInput(message);
      final signature = Signature(
        message.signature,
        publicKey: SimplePublicKey(signingPublicKey, type: KeyPairType.ed25519),
      );
      return await _ed25519.verify(input, signature: signature);
    } catch (_) {
      return false;
    }
  }
}
