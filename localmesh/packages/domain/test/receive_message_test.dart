import 'dart:convert';
import 'package:test/test.dart';
import 'package:domain/domain.dart';
import 'fakes.dart';

// Identities used across tests
const _alice = LocalMeshIdentity(
  displayName: 'Alice',
  signingPublicKey: [10],
  signingPrivateKey: [20],
  encryptionPublicKey: [30],
  encryptionPrivateKey: [40],
  fingerprint: 'alice-fingerprint0', // exactly 16 chars
);

const _bob = Peer(
  id: 'bob-fingerprint000', // exactly 16 chars
  displayName: 'Bob',
  signingPublicKey: [50],
  encryptionPublicKey: [60],
  lastSeen: 0,
  isConnected: true,
  isTrusted: true,
);

// Bob's public key used by the router lookup
final _routerLookup = {_bob.id: _bob.signingPublicKey};

ReceiveMessage _makeReceiveMessage({
  MessageEncryptor? encryptor,
  LamportClock? clock,
  FakeIdentityRepository? identityRepo,
  FakePeerRepository? peerRepo,
  FakeMessageRepository? messageRepo,
}) {
  final router = MeshRouter(
    signer: FakeMessageSigner(),
    myFingerprint: _alice.fingerprint,
    lookupSenderPublicKey: (id) async => _routerLookup[id],
  );
  return ReceiveMessage(
    router: router,
    identityRepo: identityRepo ?? FakeIdentityRepository(),
    peerRepo: peerRepo ?? FakePeerRepository(),
    messageRepo: messageRepo ?? FakeMessageRepository(),
    encryptor: encryptor ?? FakeMessageEncryptor(),
    keyDeriver: FakeSessionKeyDeriver(),
    clock: clock ?? LamportClock(),
  );
}

LocalMeshMessage _makeMsg({
  String? recipientId,
  List<int>? payload,
  int hopCount = 0,
  int ttl = 5,
  int lamportTs = 5,
}) {
  return LocalMeshMessage(
    id: 'msg-bob-1',
    version: 1,
    type: MessageType.text,
    senderId: _bob.id,
    recipientId: recipientId ?? _alice.fingerprint,
    payload: payload ?? const [],
    hopCount: hopCount,
    ttl: ttl,
    lamportTs: lamportTs,
    signature: const [1, 2, 3, 4], // valid for FakeMessageSigner
    createdAt: 0,
  );
}

void main() {
  group('ReceiveMessage', () {
    test('1. dropped by router — no persistence, no decryption', () async {
      // Send a duplicate: first call processes it, second drops it
      final identityRepo = FakeIdentityRepository();
      final peerRepo = FakePeerRepository();
      final messageRepo = FakeMessageRepository();

      await identityRepo.saveIdentity(_alice);
      await peerRepo.savePeer(_bob);

      final receive = _makeReceiveMessage(
        identityRepo: identityRepo,
        peerRepo: peerRepo,
        messageRepo: messageRepo,
      );
      final msg = _makeMsg();

      await receive(msg); // first — processed
      final result = await receive(msg); // second — duplicate drop

      expect(result.decision.action, RouterAction.drop);
      expect(result.decrypted, isNull);

      // Only the first call should have persisted the message
      final stored = await messageRepo.getMessageById(msg.id);
      expect(stored, isNotNull); // first call did persist it
    });

    test('2. delivered and decryptable: persisted, plaintext matches', () async {
      final identityRepo = FakeIdentityRepository();
      final peerRepo = FakePeerRepository();
      final messageRepo = FakeMessageRepository();

      await identityRepo.saveIdentity(_alice);
      await peerRepo.savePeer(_bob);

      final encryptor = FakeMessageEncryptor();
      final keyDeriver = FakeSessionKeyDeriver();
      const plaintext = 'hello from bob';

      // Pre-encrypt using the same fake key deriver so ReceiveMessage can invert it
      final sessionKey = await keyDeriver.deriveSessionKey(
        myPrivateKey: _bob.encryptionPublicKey, // not used by fake
        theirPublicKey: _alice.encryptionPublicKey,
        myFingerprint: _bob.id,
        theirFingerprint: _alice.fingerprint,
      );
      final encryptedPayload = await encryptor.encrypt(
        plaintext: utf8.encode(plaintext),
        sessionKey: sessionKey,
      );

      final receive = _makeReceiveMessage(
        encryptor: encryptor,
        identityRepo: identityRepo,
        peerRepo: peerRepo,
        messageRepo: messageRepo,
      );
      final msg = _makeMsg(payload: encryptedPayload);
      final result = await receive(msg);

      expect(result.decision.action, isNot(RouterAction.drop));
      expect(result.decrypted, isNotNull);
      expect(result.decrypted!.plaintext, plaintext);

      final stored = await messageRepo.getMessageById(msg.id);
      expect(stored, isNotNull);
    });

    test('3. delivered but decryption throws: envelope persisted, decrypted null', () async {
      final identityRepo = FakeIdentityRepository();
      final peerRepo = FakePeerRepository();
      final messageRepo = FakeMessageRepository();

      await identityRepo.saveIdentity(_alice);
      await peerRepo.savePeer(_bob);

      final receive = _makeReceiveMessage(
        encryptor: ThrowingMessageEncryptor(),
        identityRepo: identityRepo,
        peerRepo: peerRepo,
        messageRepo: messageRepo,
      );
      final msg = _makeMsg(payload: [1, 2, 3]);
      final result = await receive(msg);

      // Router delivered it, but decryption failed
      expect(result.decrypted, isNull);

      // Envelope must still be persisted
      final stored = await messageRepo.getMessageById(msg.id);
      expect(stored, isNotNull);
    });

    test('4. Lamport clock merges correctly on delivery', () async {
      final identityRepo = FakeIdentityRepository();
      final peerRepo = FakePeerRepository();

      await identityRepo.saveIdentity(_alice);
      await peerRepo.savePeer(_bob);

      final clock = LamportClock(initialValue: 1);
      final receive = _makeReceiveMessage(
        identityRepo: identityRepo,
        peerRepo: peerRepo,
        clock: clock,
      );

      // Message has lamportTs=10; clock starts at 1 → merge → max(1,10)+1 = 11
      final msg = _makeMsg(lamportTs: 10);
      await receive(msg);

      expect(clock.value, 11);
    });

    test('5. forward-only: decrypted null, forwardMessage has incremented hopCount', () async {
      // Message addressed to a third peer (not alice) — router should forward only
      final receive = _makeReceiveMessage();
      final msg = _makeMsg(recipientId: 'peer-c', hopCount: 0, ttl: 5);
      final result = await receive(msg);

      expect(result.decision.action, RouterAction.forwardOnly);
      expect(result.decrypted, isNull);
      expect(result.decision.forwardMessage, isNotNull);
      expect(result.decision.forwardMessage!.hopCount, 1);
    });
  });

  group('ReceiveMessage — content-type filtering', () {
    test('6. PEER_ANNOUNCE messages are NOT saved to the message repository', () async {
      final identityRepo = FakeIdentityRepository();
      final peerRepo = FakePeerRepository();
      final messageRepo = FakeMessageRepository();

      await identityRepo.saveIdentity(_alice);
      await peerRepo.savePeer(_bob);

      final receive = _makeReceiveMessage(
        identityRepo: identityRepo,
        peerRepo: peerRepo,
        messageRepo: messageRepo,
      );

      final announceMsg = LocalMeshMessage(
        id: 'msg-announce-1',
        version: 1,
        type: MessageType.peerAnnounce,
        senderId: _bob.id,
        recipientId: '*',
        payload: const [],
        hopCount: 0,
        ttl: 5,
        lamportTs: 3,
        signature: const [1, 2, 3, 4], // valid for FakeMessageSigner
        createdAt: 0,
      );

      await receive(announceMsg);

      final stored = await messageRepo.getMessageById(announceMsg.id);
      expect(stored, isNull, reason: 'PEER_ANNOUNCE must not be persisted to the message repository');
    });

    test('7. SYNC_REQUEST messages are NOT saved to the message repository', () async {
      final identityRepo = FakeIdentityRepository();
      final peerRepo = FakePeerRepository();
      final messageRepo = FakeMessageRepository();

      await identityRepo.saveIdentity(_alice);
      await peerRepo.savePeer(_bob);

      final receive = _makeReceiveMessage(
        identityRepo: identityRepo,
        peerRepo: peerRepo,
        messageRepo: messageRepo,
      );

      final syncMsg = LocalMeshMessage(
        id: 'msg-sync-1',
        version: 1,
        type: MessageType.syncRequest,
        senderId: _bob.id,
        recipientId: '*',
        payload: const [],
        hopCount: 0,
        ttl: 5,
        lamportTs: 4,
        signature: const [1, 2, 3, 4],
        createdAt: 0,
      );

      await receive(syncMsg);

      final stored = await messageRepo.getMessageById(syncMsg.id);
      expect(stored, isNull, reason: 'SYNC_REQUEST must not be persisted to the message repository');
    });

    test('8. TEXT messages are still saved (regression guard)', () async {
      final identityRepo = FakeIdentityRepository();
      final peerRepo = FakePeerRepository();
      final messageRepo = FakeMessageRepository();

      await identityRepo.saveIdentity(_alice);
      await peerRepo.savePeer(_bob);

      final receive = _makeReceiveMessage(
        identityRepo: identityRepo,
        peerRepo: peerRepo,
        messageRepo: messageRepo,
      );

      final textMsg = _makeMsg();
      await receive(textMsg);

      final stored = await messageRepo.getMessageById(textMsg.id);
      expect(stored, isNotNull, reason: 'TEXT messages must still be persisted');
    });
  });
}
