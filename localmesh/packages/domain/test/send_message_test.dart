import 'package:test/test.dart';
import 'package:domain/domain.dart';
import 'fakes.dart';

void main() {
  late FakeIdentityRepository identityRepo;
  late FakePeerRepository peerRepo;
  late FakeMessageRepository messageRepo;
  late FakeMessageEncryptor encryptor;
  late FakeMessageSigner signer;
  late FakeSessionKeyDeriver keyDeriver;
  late LamportClock clock;
  late SendMessage sendMessage;

  setUp(() {
    identityRepo = FakeIdentityRepository();
    peerRepo = FakePeerRepository();
    messageRepo = FakeMessageRepository();
    encryptor = FakeMessageEncryptor();
    signer = FakeMessageSigner();
    keyDeriver = FakeSessionKeyDeriver();
    clock = LamportClock();
    sendMessage = SendMessage(
      identityRepo: identityRepo,
      peerRepo: peerRepo,
      messageRepo: messageRepo,
      encryptor: encryptor,
      signer: signer,
      keyDeriver: keyDeriver,
      clock: clock,
    );
  });

  test('1. throws StateError when no identity exists', () {
    expect(
      () => sendMessage(recipientId: 'anyone', plaintext: 'hello'),
      throwsStateError,
    );
  });

  test('2. throws ArgumentError when recipient peer is unknown', () async {
    await identityRepo.saveIdentity(const LocalMeshIdentity(
      displayName: 'Alice',
      signingPublicKey: [1],
      signingPrivateKey: [2],
      encryptionPublicKey: [3],
      encryptionPrivateKey: [4],
      fingerprint: 'alice-fp-0123456',
    ));
    expect(
      () => sendMessage(recipientId: 'unknown-peer', plaintext: 'hello'),
      throwsArgumentError,
    );
  });

  group('happy path', () {
    const alice = LocalMeshIdentity(
      displayName: 'Alice',
      signingPublicKey: [1],
      signingPrivateKey: [2],
      encryptionPublicKey: [3],
      encryptionPrivateKey: [4],
      fingerprint: 'alice-fp-0123456',
    );
    const bob = Peer(
      id: 'bob-fp-00123456',
      displayName: 'Bob',
      signingPublicKey: [5],
      encryptionPublicKey: [6],
      lastSeen: 0,
      isConnected: true,
      isTrusted: true,
    );

    setUp(() async {
      await identityRepo.saveIdentity(alice);
      await peerRepo.savePeer(bob);
    });

    test('3. returns message with correct sender, recipient, TTL, lamportTs and hopCount', () async {
      final msg = await sendMessage(
        recipientId: bob.id,
        plaintext: 'hello world',
        ttl: 3,
      );
      expect(msg.senderId, alice.fingerprint);
      expect(msg.recipientId, bob.id);
      expect(msg.ttl, 3);
      expect(msg.lamportTs, 1); // first tick on a fresh clock
      expect(msg.hopCount, 0);
      expect(msg.version, 1);
    });

    test('4. persists the message to the repository before returning', () async {
      final msg = await sendMessage(recipientId: bob.id, plaintext: 'persist me');
      final stored = await messageRepo.getMessageById(msg.id);
      expect(stored, isNotNull);
      expect(stored!.id, msg.id);
    });

    test('5. successive sends have strictly increasing lamportTs', () async {
      final msg1 = await sendMessage(recipientId: bob.id, plaintext: 'first');
      final msg2 = await sendMessage(recipientId: bob.id, plaintext: 'second');
      expect(msg2.lamportTs, greaterThan(msg1.lamportTs));
    });

    test('6. signature is the FakeSigner sentinel [1,2,3,4]', () async {
      final msg = await sendMessage(recipientId: bob.id, plaintext: 'signed');
      expect(msg.signature, isNotEmpty);
      expect(msg.signature, [1, 2, 3, 4]);
    });
  });
}
