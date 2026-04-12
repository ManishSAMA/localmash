import 'package:crypto_layer/crypto_layer.dart';
import 'package:test/test.dart';

void main() {
  group('IdentityService', () {
    late IdentityService service;

    setUp(() {
      service = IdentityService();
    });

    test('generates non-empty key pairs with correct lengths', () async {
      final identity = await service.generateIdentity('Alice');

      expect(identity.signingPublicKey, hasLength(32));
      expect(identity.signingPrivateKey, hasLength(32));
      expect(identity.encryptionPublicKey, hasLength(32));
      expect(identity.encryptionPrivateKey, hasLength(32));
      expect(identity.displayName, equals('Alice'));
    });

    test('two calls produce different identities', () async {
      final a = await service.generateIdentity('Alice');
      final b = await service.generateIdentity('Alice');

      expect(a.signingPublicKey, isNot(equals(b.signingPublicKey)));
      expect(a.encryptionPublicKey, isNot(equals(b.encryptionPublicKey)));
    });

    test('fingerprint is exactly 16 hex characters', () async {
      final identity = await service.generateIdentity('Alice');

      expect(identity.fingerprint, hasLength(16));
      expect(
        RegExp(r'^[0-9a-f]{16}$').hasMatch(identity.fingerprint),
        isTrue,
      );
    });

    test('fingerprint is deterministic for the same public key', () async {
      final identity = await service.generateIdentity('Alice');

      final fp1 = await service.computeFingerprint(identity.signingPublicKey);
      final fp2 = await service.computeFingerprint(identity.signingPublicKey);

      expect(fp1, equals(fp2));
      expect(fp1, equals(identity.fingerprint));
    });

    test('different public keys produce different fingerprints', () async {
      final a = await service.generateIdentity('Alice');
      final b = await service.generateIdentity('Bob');

      expect(a.fingerprint, isNot(equals(b.fingerprint)));
    });
  });
}
