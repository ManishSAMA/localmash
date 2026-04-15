// See message_signer.dart for the rationale behind putting this interface
// in the domain layer rather than in crypto_layer.

import 'dart:typed_data';

abstract class MessageEncryptor {
  Future<Uint8List> encrypt({
    required List<int> plaintext,
    required List<int> sessionKey,
  });

  Future<Uint8List> decrypt({
    required List<int> encrypted,
    required List<int> sessionKey,
  });
}
