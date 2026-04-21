// Three-node relay integration test.
//
// Topology: A ──── B ──── C   (A and C are NOT directly connected)
//
// A sends "hello C" addressed to C's fingerprint.
// The message must arrive at C decrypted, via B as relay.
//
// Exercises: MessageController, WireCodec, MeshRouter, SendMessage,
// ReceiveMessage, FakeMessageEncryptor, FakeMessageSigner, MockTransport,
// FakePeerRepository, FakeMessageRepository, FakeIdentityRepository.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:domain/domain.dart';
import 'package:transport/transport_package.dart';
import 'package:localmesh/controllers/message_controller.dart';

// ── Inline fakes ─────────────────────────────────────────────────────────────

class _FakeMessageRepository implements MessageRepository {
  final Map<String, LocalMeshMessage> _byId = {};
  final Map<String, List<LocalMeshMessage>> _byRoom = {};

  @override
  Future<void> saveMessage(LocalMeshMessage message) async {
    _byId[message.id] = message;
    _byRoom.putIfAbsent(message.recipientId, () => []).add(message);
  }

  @override
  Future<List<LocalMeshMessage>> getMessagesForChat(String chatRoomId,
      {int? afterLamportTs, int limit = 100}) async {
    final msgs = _byRoom[chatRoomId] ?? [];
    return msgs
        .where((m) => afterLamportTs == null || m.lamportTs > afterLamportTs)
        .take(limit)
        .toList();
  }

  @override
  Future<LocalMeshMessage?> getMessageById(String id) async => _byId[id];

  @override
  Future<bool> hasMessage(String id) async => _byId.containsKey(id);

  @override
  Future<int> getHighestLamportTsForChat(String chatRoomId) async {
    final msgs = _byRoom[chatRoomId] ?? [];
    if (msgs.isEmpty) return 0;
    return msgs.map((m) => m.lamportTs).reduce((a, b) => a > b ? a : b);
  }

  @override
  Future<void> deleteMessage(String id) async {
    final msg = _byId.remove(id);
    if (msg != null) _byRoom[msg.recipientId]?.remove(msg);
  }
}

class _FakePeerRepository implements PeerRepository {
  final Map<String, Peer> _peers = {};

  @override
  Future<void> savePeer(Peer peer) async => _peers[peer.id] = peer;

  @override
  Future<Peer?> getPeerById(String id) async => _peers[id];

  @override
  Future<List<Peer>> getAllPeers() async => _peers.values.toList();

  @override
  Future<List<Peer>> getConnectedPeers() async =>
      _peers.values.where((p) => p.isConnected).toList();

  @override
  Future<List<Peer>> getTrustedPeers() async =>
      _peers.values.where((p) => p.isTrusted).toList();

  @override
  Future<void> updatePeerConnectionStatus(String id, bool isConnected) async {
    final peer = _peers[id];
    if (peer != null) _peers[id] = peer.copyWith(isConnected: isConnected);
  }

  @override
  Future<void> removePeer(String id) async => _peers.remove(id);
}

class _FakeIdentityRepository implements IdentityRepository {
  LocalMeshIdentity? _identity;

  @override
  Future<void> saveIdentity(LocalMeshIdentity identity) async =>
      _identity = identity;

  @override
  Future<LocalMeshIdentity?> getIdentity() async => _identity;

  @override
  Future<bool> hasIdentity() async => _identity != null;

  @override
  Future<void> deleteIdentity() async => _identity = null;
}

class _FakeSigner implements MessageSigner {
  static const _sig = [1, 2, 3, 4];

  @override
  Future<List<int>> sign({
    required LocalMeshMessage message,
    required List<int> signingPrivateKey,
    required List<int> signingPublicKey,
  }) async =>
      List<int>.from(_sig);

  @override
  Future<bool> verify({
    required LocalMeshMessage message,
    required List<int> signingPublicKey,
  }) async {
    final s = message.signature;
    if (s.length != _sig.length) return false;
    for (var i = 0; i < _sig.length; i++) {
      if (s[i] != _sig[i]) return false;
    }
    return true;
  }
}

class _FakeEncryptor implements MessageEncryptor {
  @override
  Future<Uint8List> encrypt(
          {required List<int> plaintext, required List<int> sessionKey}) async =>
      Uint8List.fromList(plaintext.map((b) => b ^ sessionKey[0]).toList());

  @override
  Future<Uint8List> decrypt(
          {required List<int> encrypted, required List<int> sessionKey}) async =>
      Uint8List.fromList(encrypted.map((b) => b ^ sessionKey[0]).toList());
}

class _FakeKeyDeriver implements SessionKeyDeriver {
  @override
  Future<List<int>> deriveSessionKey({
    required List<int> myPrivateKey,
    required List<int> theirPublicKey,
    required String myFingerprint,
    required String theirFingerprint,
  }) async {
    final sorted = [myFingerprint, theirFingerprint]..sort();
    final combined = sorted.join(':');
    final bytes = List<int>.filled(32, 0);
    for (var i = 0; i < combined.length && i < 32; i++) {
      bytes[i] = combined.codeUnitAt(i) & 0xFF;
    }
    return bytes;
  }
}

class _FakeIdentityGenerator implements IdentityGenerator {
  @override
  Future<LocalMeshIdentity> generate(String displayName) async {
    final fp = await computeFingerprint(List.filled(32, displayName.codeUnitAt(0)));
    return LocalMeshIdentity(
      displayName: displayName,
      signingPublicKey: List.filled(32, displayName.codeUnitAt(0)),
      signingPrivateKey: List.filled(32, displayName.codeUnitAt(0) + 1),
      encryptionPublicKey: List.filled(32, displayName.codeUnitAt(0) + 2),
      encryptionPrivateKey: List.filled(32, displayName.codeUnitAt(0) + 3),
      fingerprint: fp,
    );
  }

  @override
  Future<String> computeFingerprint(List<int> signingPublicKey) async =>
      signingPublicKey
          .take(8)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
}

// ── Node builder ─────────────────────────────────────────────────────────────

class _Node {
  _Node({
    required this.identity,
    required this.transport,
    required this.peerRepo,
    required this.messageRepo,
    required this.controller,
  });

  final LocalMeshIdentity identity;
  final MockTransport transport;
  final _FakePeerRepository peerRepo;
  final _FakeMessageRepository messageRepo;
  final MessageController controller;

  String get fp => identity.fingerprint;
}

Future<_Node> _buildNode(String name) async {
  final identity = await _FakeIdentityGenerator().generate(name);

  final transport = MockTransport(peerId: identity.fingerprint);
  final peerRepo = _FakePeerRepository();
  final identityRepo = _FakeIdentityRepository();
  final messageRepo = _FakeMessageRepository();
  final signer = _FakeSigner();
  final encryptor = _FakeEncryptor();
  final keyDeriver = _FakeKeyDeriver();
  final clock = LamportClock();

  await identityRepo.saveIdentity(identity);

  final router = MeshRouter(
    signer: signer,
    myFingerprint: identity.fingerprint,
    lookupSenderPublicKey: (senderId) async {
      final peer = await peerRepo.getPeerById(senderId);
      return peer?.signingPublicKey;
    },
  );

  final receiveMessage = ReceiveMessage(
    router: router,
    identityRepo: identityRepo,
    peerRepo: peerRepo,
    messageRepo: messageRepo,
    encryptor: encryptor,
    keyDeriver: keyDeriver,
    clock: clock,
  );

  final sendMessage = SendMessage(
    identityRepo: identityRepo,
    peerRepo: peerRepo,
    messageRepo: messageRepo,
    encryptor: encryptor,
    signer: signer,
    keyDeriver: keyDeriver,
    clock: clock,
  );

  final manager = TransportManager([transport]);
  await manager.start();

  final controller = MessageController(
    transportManager: manager,
    receiveMessage: receiveMessage,
    sendMessage: sendMessage,
    syncHistory: SyncHistory(messageRepo: messageRepo),
    peerRepo: peerRepo,
    identityRepo: identityRepo,
    signer: signer,
    identityGenerator: _FakeIdentityGenerator(),
  );
  await controller.start();

  return _Node(
    identity: identity,
    transport: transport,
    peerRepo: peerRepo,
    messageRepo: messageRepo,
    controller: controller,
  );
}

Future<void> _registerPeer(_Node host, _Node remote) async {
  await host.peerRepo.savePeer(Peer(
    id: remote.fp,
    displayName: remote.identity.displayName,
    signingPublicKey: remote.identity.signingPublicKey,
    encryptionPublicKey: remote.identity.encryptionPublicKey,
    lastSeen: DateTime.now().millisecondsSinceEpoch,
    isConnected: true,
    isTrusted: true,
  ));
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('3-node relay', () {
    late _Node nodeA;
    late _Node nodeB;
    late _Node nodeC;

    setUp(() async {
      nodeA = await _buildNode('Alice');
      nodeB = await _buildNode('Bob');
      nodeC = await _buildNode('Carol');

      // Topology: A ── B ── C  (A and C are NOT directly linked)
      nodeA.transport.linkTo(nodeB.transport);
      nodeB.transport.linkTo(nodeC.transport);

      // Pre-register all peers so signature verification and encryption work
      await _registerPeer(nodeA, nodeB);
      await _registerPeer(nodeA, nodeC);
      await _registerPeer(nodeB, nodeA);
      await _registerPeer(nodeB, nodeC);
      await _registerPeer(nodeC, nodeA);
      await _registerPeer(nodeC, nodeB);
    });

    tearDown(() async {
      await nodeA.controller.dispose();
      await nodeB.controller.dispose();
      await nodeC.controller.dispose();
    });

    test('A sends to C, C receives decrypted via B relay', () async {
      final cDecrypted = <DecryptedMessage>[];
      final sub = nodeC.controller.decryptedMessages.listen(cDecrypted.add);

      await nodeA.controller.sendText(
        recipientId: nodeC.fp,
        plaintext: 'hello C',
      );

      // Allow async relay chain to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(cDecrypted, hasLength(1));
      expect(cDecrypted.first.plaintext, equals('hello C'));

      // hopCount must reflect one relay hop (A→B→C)
      expect(cDecrypted.first.envelope.hopCount, equals(1));

      // C's repo must persist the envelope.
      // Messages addressed TO C are stored under C's fingerprint (recipientId).
      final stored = await nodeC.messageRepo.getMessagesForChat(nodeC.fp);
      expect(stored, isNotEmpty);
    });

    test('B does not deliver message addressed to C into B repo', () async {
      final sub = nodeC.controller.decryptedMessages.listen((_) {});

      await nodeA.controller.sendText(
        recipientId: nodeC.fp,
        plaintext: 'relay check',
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      // B forwards the message (forwardOnly) — it should NOT be in B's repo
      final bStored = await nodeB.messageRepo.getMessagesForChat(nodeA.fp);
      expect(bStored, isEmpty);
    });

    test('sync: C recovers missed messages after reconnect via B', () async {
      // Phase 1 — A sends while C is disconnected from B
      nodeB.transport.unlinkFrom(nodeC.transport);

      await nodeA.controller.sendText(
        recipientId: nodeC.fp,
        plaintext: 'offline message',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // C received nothing — messages to C are stored under nodeC.fp
      final beforeSync = await nodeC.messageRepo.getMessagesForChat(nodeC.fp);
      expect(beforeSync, isEmpty);

      // Phase 2 — Manually place the missed message into B's repo (simulates
      // B having relayed and stored it while C was offline)
      final sentByA = await nodeA.messageRepo.getMessagesForChat(nodeC.fp);
      for (final m in sentByA) {
        await nodeB.messageRepo.saveMessage(m);
      }

      // Phase 3 — C reconnects; linkTo fires PeerEvent → sync handshake
      final cDecrypted = <DecryptedMessage>[];
      final sub = nodeC.controller.decryptedMessages.listen(cDecrypted.add);

      nodeB.transport.linkTo(nodeC.transport);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      expect(cDecrypted, hasLength(greaterThanOrEqualTo(1)));
      expect(
        cDecrypted.any((d) => d.plaintext == 'offline message'),
        isTrue,
        reason: 'C should recover the missed message via sync',
      );
    });
  });
}
