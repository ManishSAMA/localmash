import 'dart:convert';
import 'package:crypto_layer/crypto_layer.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  test('end-to-end: Alice encrypts and signs, Bob decrypts and verifies',
      () async {
    final identityService = IdentityService();
    final keyExchange = KeyExchangeService();
    final encryption = EncryptionService();
    final signing = SigningService();

    // 1. Both peers have identities
    final alice = await identityService.generateIdentity('Alice');
    final bob = await identityService.generateIdentity('Bob');

    // 2. Both derive the same session key
    final aliceKey = await keyExchange.deriveSessionKey(
      myPrivateKey: alice.encryptionPrivateKey,
      theirPublicKey: bob.encryptionPublicKey,
      myFingerprint: alice.fingerprint,
      theirFingerprint: bob.fingerprint,
    );
    final bobKey = await keyExchange.deriveSessionKey(
      myPrivateKey: bob.encryptionPrivateKey,
      theirPublicKey: alice.encryptionPublicKey,
      myFingerprint: bob.fingerprint,
      theirFingerprint: alice.fingerprint,
    );
    expect(aliceKey, equals(bobKey));

    // 3. Alice encrypts a message
    final plaintext = utf8.encode('Hello Bob, this is Alice');
    final encryptedPayload = await encryption.encrypt(
      plaintext: plaintext,
      sessionKey: aliceKey,
    );

    // 4. Alice builds and signs a LocalMeshMessage
    var message = LocalMeshMessage(
      id: 'test-message-id-001',
      version: 1,
      type: MessageType.text,
      senderId: alice.fingerprint,
      recipientId: bob.fingerprint,
      payload: encryptedPayload,
      hopCount: 0,
      ttl: 5,
      lamportTs: 1,
      signature: const [],
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    final signature = await signing.signMessage(
      message: message,
      signingPrivateKey: alice.signingPrivateKey,
      signingPublicKey: alice.signingPublicKey,
    );

    message = LocalMeshMessage(
      id: message.id,
      version: message.version,
      type: message.type,
      senderId: message.senderId,
      recipientId: message.recipientId,
      payload: message.payload,
      hopCount: message.hopCount,
      ttl: message.ttl,
      lamportTs: message.lamportTs,
      signature: signature,
      createdAt: message.createdAt,
    );

    // 5. Bob verifies the signature using Alice's public key
    final verified = await signing.verifyMessage(
      message: message,
      signingPublicKey: alice.signingPublicKey,
    );
    expect(verified, isTrue);

    // 6. Bob decrypts the payload
    final decrypted = await encryption.decrypt(
      encrypted: message.payload,
      sessionKey: bobKey,
    );
    expect(utf8.decode(decrypted), equals('Hello Bob, this is Alice'));
  });
}
