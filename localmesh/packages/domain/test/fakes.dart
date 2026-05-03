// In-memory fakes for unit-testing the domain layer.
// These implement domain interfaces directly — no crypto_layer, no Hive.
// All fakes live here so individual test files just import 'fakes.dart'.

import 'dart:typed_data';
import 'package:domain/domain.dart';

// ---------------------------------------------------------------------------
// FakeMessageRepository
// ---------------------------------------------------------------------------

class FakeMessageRepository implements MessageRepository {
  final Map<String, LocalMeshMessage> _byId = {};
  final Map<String, List<LocalMeshMessage>> _byRoom = {};

  @override
  Future<void> saveMessage(LocalMeshMessage message) async {
    final old = _byId[message.id];
    if (old != null) {
      _byRoom[old.recipientId]?.removeWhere((m) => m.id == message.id);
    }
    _byId[message.id] = message;
    _byRoom.putIfAbsent(message.recipientId, () => []).add(message);
  }

  @override
  Future<void> updateMessage(LocalMeshMessage message) => saveMessage(message);

  @override
  Future<List<LocalMeshMessage>> getMessagesForChat(
    String chatRoomId, {
    int? afterLamportTs,
    int limit = 100,
  }) async {
    final messages = _byRoom[chatRoomId] ?? [];
    return messages
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
    final messages = _byRoom[chatRoomId] ?? [];
    if (messages.isEmpty) return 0;
    return messages.map((m) => m.lamportTs).reduce((a, b) => a > b ? a : b);
  }

  @override
  Future<void> deleteMessage(String id) async {
    final msg = _byId.remove(id);
    if (msg != null) {
      _byRoom[msg.recipientId]?.remove(msg);
    }
  }
}

// ---------------------------------------------------------------------------
// FakePeerRepository
// ---------------------------------------------------------------------------

class FakePeerRepository implements PeerRepository {
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
  Future<void> trustPeer(String id) async {
    final peer = _peers[id];
    if (peer != null) _peers[id] = peer.copyWith(isTrusted: true);
  }

  @override
  Future<void> removePeer(String id) async => _peers.remove(id);
}

// ---------------------------------------------------------------------------
// FakeIdentityRepository
// ---------------------------------------------------------------------------

class FakeIdentityRepository implements IdentityRepository {
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

// ---------------------------------------------------------------------------
// FakeMessageSigner
// ---------------------------------------------------------------------------
// Always signs with [1, 2, 3, 4].  Verifies true iff signature == [1, 2, 3, 4].

class FakeMessageSigner implements MessageSigner {
  static const _validSig = [1, 2, 3, 4];

  @override
  Future<List<int>> sign({
    required LocalMeshMessage message,
    required List<int> signingPrivateKey,
    required List<int> signingPublicKey,
  }) async =>
      List<int>.from(_validSig);

  @override
  Future<bool> verify({
    required LocalMeshMessage message,
    required List<int> signingPublicKey,
  }) async {
    final sig = message.signature;
    if (sig.length != _validSig.length) return false;
    for (var i = 0; i < _validSig.length; i++) {
      if (sig[i] != _validSig[i]) return false;
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// FakeMessageEncryptor
// ---------------------------------------------------------------------------
// XOR plaintext with sessionKey[0].  Reversible — not secure, test only.

class FakeMessageEncryptor implements MessageEncryptor {
  @override
  Future<Uint8List> encrypt({
    required List<int> plaintext,
    required List<int> sessionKey,
  }) async {
    final key = sessionKey[0];
    return Uint8List.fromList(plaintext.map((b) => b ^ key).toList());
  }

  @override
  Future<Uint8List> decrypt({
    required List<int> encrypted,
    required List<int> sessionKey,
  }) async {
    final key = sessionKey[0];
    return Uint8List.fromList(encrypted.map((b) => b ^ key).toList());
  }
}

// ---------------------------------------------------------------------------
// ThrowingMessageEncryptor
// ---------------------------------------------------------------------------
// Encrypt is identity; decrypt always throws.  Used to test error-path in
// ReceiveMessage where decryption fails but the envelope is still persisted.

class ThrowingMessageEncryptor implements MessageEncryptor {
  @override
  Future<Uint8List> encrypt({
    required List<int> plaintext,
    required List<int> sessionKey,
  }) async =>
      Uint8List.fromList(plaintext);

  @override
  Future<Uint8List> decrypt({
    required List<int> encrypted,
    required List<int> sessionKey,
  }) async =>
      throw Exception('simulated decryption failure');
}

// ---------------------------------------------------------------------------
// FakeSessionKeyDeriver
// ---------------------------------------------------------------------------
// Sorts the two fingerprints, concatenates them, and fills a 32-byte key
// from the resulting string's code units.  Identical result regardless of
// which peer "calls first" because of the sort.

class FakeSessionKeyDeriver implements SessionKeyDeriver {
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

// ---------------------------------------------------------------------------
// FakeIdentityGenerator
// ---------------------------------------------------------------------------
// Produces LocalMeshIdentity with deterministic, predictable key bytes so
// tests can assert on fingerprints without running real crypto.

class FakeIdentityGenerator implements IdentityGenerator {
  @override
  Future<LocalMeshIdentity> generate(String displayName) async {
    final fp = await computeFingerprint(List.filled(32, 1));
    return LocalMeshIdentity(
      displayName: displayName,
      signingPublicKey: List.filled(32, 1),
      signingPrivateKey: List.filled(32, 2),
      encryptionPublicKey: List.filled(32, 3),
      encryptionPrivateKey: List.filled(32, 4),
      fingerprint: fp,
    );
  }

  @override
  Future<String> computeFingerprint(List<int> signingPublicKey) async {
    // 16-char hex of first 8 bytes
    return signingPublicKey
        .take(8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
