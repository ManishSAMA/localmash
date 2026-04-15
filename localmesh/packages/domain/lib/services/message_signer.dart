// This interface is defined here (not in crypto_layer) because the domain
// layer owns its dependencies. crypto_layer implements this interface, and
// the root app wires the implementation in via service_locator.dart.
// This keeps domain pure Dart with zero crypto library dependencies.

import '../entities/message.dart';

abstract class MessageSigner {
  Future<List<int>> sign({
    required LocalMeshMessage message,
    required List<int> signingPrivateKey,
    required List<int> signingPublicKey,
  });

  Future<bool> verify({
    required LocalMeshMessage message,
    required List<int> signingPublicKey,
  });
}
