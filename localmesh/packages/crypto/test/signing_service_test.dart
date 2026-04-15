import 'dart:typed_data';
import 'package:crypto_layer/crypto_layer.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

LocalMeshMessage _makeMessage({
  String id = 'msg-001',
  String senderId = 'aabbccdd11223344',
  String recipientId = 'deadbeef12345678',
  List<int>? payload,
  int hopCount = 0,
  int ttl = 5,
  int lamportTs = 1,
  List<int>? signature,
}) {
  return LocalMeshMessage(
    id: id,
    version: 1,
    type: MessageType.text,
    senderId: senderId,
    recipientId: recipientId,
    payload: payload ?? Uint8List(4),
    hopCount: hopCount,
    ttl: ttl,
    lamportTs: lamportTs,
    signature: signature ?? const [],
    createdAt: 0,
  );
}

void main() {
  group('SigningService', () {
    late IdentityService identityService;
    late SigningService signingService;

    setUp(() {
      identityService = IdentityService();
      signingService = SigningService();
    });

    test('message signed with Alice key verifies with Alice public key',
        () async {
      final alice = await identityService.generate('Alice');
      final msg = _makeMessage(senderId: alice.fingerprint);

      final sigBytes = await signingService.sign(
        message: msg,
        signingPrivateKey: alice.signingPrivateKey,
        signingPublicKey: alice.signingPublicKey,
      );
      final signed = _makeMessage(
        senderId: alice.fingerprint,
        signature: sigBytes,
      );

      final valid = await signingService.verify(
        message: signed,
        signingPublicKey: alice.signingPublicKey,
      );
      expect(valid, isTrue);
    });

    test('message signed with Alice key does NOT verify with Bob public key',
        () async {
      final alice = await identityService.generate('Alice');
      final bob = await identityService.generate('Bob');
      final msg = _makeMessage(senderId: alice.fingerprint);

      final sigBytes = await signingService.sign(
        message: msg,
        signingPrivateKey: alice.signingPrivateKey,
        signingPublicKey: alice.signingPublicKey,
      );
      final signed = _makeMessage(
        senderId: alice.fingerprint,
        signature: sigBytes,
      );

      final valid = await signingService.verify(
        message: signed,
        signingPublicKey: bob.signingPublicKey,
      );
      expect(valid, isFalse);
    });

    test('tampering with payload invalidates signature', () async {
      final alice = await identityService.generate('Alice');
      final original = _makeMessage(
        senderId: alice.fingerprint,
        payload: [1, 2, 3, 4],
      );

      final sigBytes = await signingService.sign(
        message: original,
        signingPrivateKey: alice.signingPrivateKey,
        signingPublicKey: alice.signingPublicKey,
      );

      // Same message but with tampered payload
      final tampered = LocalMeshMessage(
        id: original.id,
        version: original.version,
        type: original.type,
        senderId: original.senderId,
        recipientId: original.recipientId,
        payload: const [9, 9, 9, 9],
        hopCount: original.hopCount,
        ttl: original.ttl,
        lamportTs: original.lamportTs,
        signature: sigBytes,
        createdAt: original.createdAt,
      );

      final valid = await signingService.verify(
        message: tampered,
        signingPublicKey: alice.signingPublicKey,
      );
      expect(valid, isFalse);
    });

    test('tampering with hopCount does NOT invalidate signature', () async {
      final alice = await identityService.generate('Alice');
      final original = _makeMessage(
        senderId: alice.fingerprint,
        hopCount: 0,
      );

      final sigBytes = await signingService.sign(
        message: original,
        signingPrivateKey: alice.signingPrivateKey,
        signingPublicKey: alice.signingPublicKey,
      );

      // Simulate relay: hopCount incremented but signature untouched
      final relayed = LocalMeshMessage(
        id: original.id,
        version: original.version,
        type: original.type,
        senderId: original.senderId,
        recipientId: original.recipientId,
        payload: original.payload,
        hopCount: 3,
        ttl: original.ttl,
        lamportTs: original.lamportTs,
        signature: sigBytes,
        createdAt: original.createdAt,
      );

      final valid = await signingService.verify(
        message: relayed,
        signingPublicKey: alice.signingPublicKey,
      );
      expect(valid, isTrue);
    });

    test('tampering with TTL DOES invalidate signature', () async {
      final alice = await identityService.generate('Alice');
      final original = _makeMessage(
        senderId: alice.fingerprint,
        ttl: 5,
      );

      final sigBytes = await signingService.sign(
        message: original,
        signingPrivateKey: alice.signingPrivateKey,
        signingPublicKey: alice.signingPublicKey,
      );

      final tampered = LocalMeshMessage(
        id: original.id,
        version: original.version,
        type: original.type,
        senderId: original.senderId,
        recipientId: original.recipientId,
        payload: original.payload,
        hopCount: original.hopCount,
        ttl: 99,
        lamportTs: original.lamportTs,
        signature: sigBytes,
        createdAt: original.createdAt,
      );

      final valid = await signingService.verify(
        message: tampered,
        signingPublicKey: alice.signingPublicKey,
      );
      expect(valid, isFalse);
    });

    test('empty signature returns false, does not throw', () async {
      final alice = await identityService.generate('Alice');
      final msg = _makeMessage(
        senderId: alice.fingerprint,
        signature: const [],
      );

      final valid = await signingService.verify(
        message: msg,
        signingPublicKey: alice.signingPublicKey,
      );
      expect(valid, isFalse);
    });
  });
}
