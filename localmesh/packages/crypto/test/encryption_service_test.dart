import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto_layer/crypto_layer.dart';
import 'package:test/test.dart';

void main() {
  group('EncryptionService', () {
    late EncryptionService service;
    late List<int> sessionKey;

    setUp(() {
      service = EncryptionService();
      // 32-byte key filled with 0x42
      sessionKey = List<int>.filled(32, 0x42);
    });

    test('round-trip: decrypt(encrypt(plaintext)) == plaintext', () async {
      final plaintext = utf8.encode('Hello, LocalMesh!');

      final encrypted = await service.encrypt(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );
      final decrypted = await service.decrypt(
        encrypted: encrypted,
        sessionKey: sessionKey,
      );

      expect(utf8.decode(decrypted), equals('Hello, LocalMesh!'));
    });

    test('wrong session key throws DecryptionFailedException', () async {
      final plaintext = utf8.encode('secret');
      final encrypted = await service.encrypt(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );

      final wrongKey = List<int>.filled(32, 0x99);

      expect(
        () => service.decrypt(encrypted: encrypted, sessionKey: wrongKey),
        throwsA(isA<DecryptionFailedException>()),
      );
    });

    test('tampered ciphertext throws DecryptionFailedException', () async {
      final plaintext = utf8.encode('secret');
      final encrypted = await service.encrypt(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );

      // Flip a byte in the middle of the ciphertext
      final tampered = Uint8List.fromList(encrypted);
      tampered[15] ^= 0xff;

      expect(
        () => service.decrypt(encrypted: tampered, sessionKey: sessionKey),
        throwsA(isA<DecryptionFailedException>()),
      );
    });

    test('truncated ciphertext throws DecryptionFailedException', () async {
      final plaintext = utf8.encode('secret');
      final encrypted = await service.encrypt(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );

      // Truncate to fewer than nonce(12) + tag(16) = 28 bytes
      final truncated = encrypted.sublist(0, 10);

      expect(
        () => service.decrypt(encrypted: truncated, sessionKey: sessionKey),
        throwsA(isA<DecryptionFailedException>()),
      );
    });

    test('each encryption produces a different ciphertext (random nonce)',
        () async {
      final plaintext = utf8.encode('same plaintext');

      final enc1 = await service.encrypt(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );
      final enc2 = await service.encrypt(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );

      expect(enc1, isNot(equals(enc2)));
    });

    test('output length equals plaintext length + 28', () async {
      final plaintext = utf8.encode('Hello');

      final encrypted = await service.encrypt(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );

      expect(encrypted.length, equals(plaintext.length + 28));
    });

    test('ArgumentError on session key shorter than 32 bytes', () async {
      expect(
        () => service.encrypt(
          plaintext: utf8.encode('test'),
          sessionKey: List<int>.filled(16, 0),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('ArgumentError on session key longer than 32 bytes', () async {
      expect(
        () => service.encrypt(
          plaintext: utf8.encode('test'),
          sessionKey: List<int>.filled(64, 0),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
