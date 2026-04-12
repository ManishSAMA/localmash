import 'package:crypto_layer/crypto_layer.dart';
import 'package:test/test.dart';

void main() {
  group('KeyExchangeService', () {
    late IdentityService identityService;
    late KeyExchangeService keyExchange;

    setUp(() {
      identityService = IdentityService();
      keyExchange = KeyExchangeService();
    });

    test('both peers derive identical session keys', () async {
      final alice = await identityService.generateIdentity('Alice');
      final bob = await identityService.generateIdentity('Bob');

      final aliceSessionKey = await keyExchange.deriveSessionKey(
        myPrivateKey: alice.encryptionPrivateKey,
        theirPublicKey: bob.encryptionPublicKey,
        myFingerprint: alice.fingerprint,
        theirFingerprint: bob.fingerprint,
      );

      final bobSessionKey = await keyExchange.deriveSessionKey(
        myPrivateKey: bob.encryptionPrivateKey,
        theirPublicKey: alice.encryptionPublicKey,
        myFingerprint: bob.fingerprint,
        theirFingerprint: alice.fingerprint,
      );

      expect(aliceSessionKey, equals(bobSessionKey));
      expect(aliceSessionKey.length, equals(32));
    });

    test('different peer pairs produce different session keys', () async {
      final alice = await identityService.generateIdentity('Alice');
      final bob = await identityService.generateIdentity('Bob');
      final charlie = await identityService.generateIdentity('Charlie');

      final aliceBobKey = await keyExchange.deriveSessionKey(
        myPrivateKey: alice.encryptionPrivateKey,
        theirPublicKey: bob.encryptionPublicKey,
        myFingerprint: alice.fingerprint,
        theirFingerprint: bob.fingerprint,
      );

      final aliceCharlieKey = await keyExchange.deriveSessionKey(
        myPrivateKey: alice.encryptionPrivateKey,
        theirPublicKey: charlie.encryptionPublicKey,
        myFingerprint: alice.fingerprint,
        theirFingerprint: charlie.fingerprint,
      );

      expect(aliceBobKey, isNot(equals(aliceCharlieKey)));
    });
  });
}
