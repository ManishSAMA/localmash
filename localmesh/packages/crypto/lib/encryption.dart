import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Thrown when decryption fails — wrong key, tampered ciphertext, or
/// malformed input. Never expose the underlying exception to callers
/// to avoid timing/oracle attacks.
class DecryptionFailedException implements Exception {
  DecryptionFailedException(this.message);

  final String message;

  @override
  String toString() => 'DecryptionFailedException: $message';
}

class EncryptionService {
  static const int _nonceLength = 12;
  static const int _tagLength = 16;

  final AesGcm _aesGcm = AesGcm.with256bits();

  /// Encrypts plaintext with the given 32-byte session key.
  /// Output format: [12-byte nonce][ciphertext][16-byte tag]
  /// The nonce is randomly generated per call — never reused.
  Future<Uint8List> encrypt({
    required List<int> plaintext,
    required List<int> sessionKey,
  }) async {
    if (sessionKey.length != 32) {
      throw ArgumentError('Session key must be exactly 32 bytes');
    }

    final secretKey = SecretKey(sessionKey);
    final secretBox = await _aesGcm.encrypt(
      plaintext,
      secretKey: secretKey,
    );

    // Pack: nonce || ciphertext || tag
    final result = Uint8List(
      _nonceLength + secretBox.cipherText.length + _tagLength,
    );
    result.setRange(0, _nonceLength, secretBox.nonce);
    result.setRange(
      _nonceLength,
      _nonceLength + secretBox.cipherText.length,
      secretBox.cipherText,
    );
    result.setRange(
      _nonceLength + secretBox.cipherText.length,
      result.length,
      secretBox.mac.bytes,
    );

    return result;
  }

  /// Decrypts a packed [nonce||ciphertext||tag] blob.
  /// Throws DecryptionFailedException on any failure.
  Future<Uint8List> decrypt({
    required List<int> encrypted,
    required List<int> sessionKey,
  }) async {
    if (sessionKey.length != 32) {
      throw ArgumentError('Session key must be exactly 32 bytes');
    }
    if (encrypted.length < _nonceLength + _tagLength) {
      throw DecryptionFailedException('Encrypted blob too short');
    }

    try {
      final nonce = encrypted.sublist(0, _nonceLength);
      final cipherText = encrypted.sublist(
        _nonceLength,
        encrypted.length - _tagLength,
      );
      final tag = encrypted.sublist(encrypted.length - _tagLength);

      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(tag),
      );

      final secretKey = SecretKey(sessionKey);
      final plaintext = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      return Uint8List.fromList(plaintext);
    } catch (e) {
      // Swallow underlying exception — never leak crypto error details.
      throw DecryptionFailedException('Decryption failed');
    }
  }
}
