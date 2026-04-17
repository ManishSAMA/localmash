import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:domain/domain.dart';
import 'package:transport/transport_package.dart';

/// Bidirectional bridge between the transport layer and domain use cases.
///
/// Incoming:  transport → WireCodec.decode → MeshRouter → deliver/forward
/// Outgoing:  SendMessage → WireCodec.encode → TransportManager.broadcast
///
/// Also owns the sync handshake: sends a SYNC_REQUEST to every newly-connected
/// peer and processes SYNC_REQUEST responses by replaying missing messages.
class MessageController {
  MessageController({
    required TransportManager transportManager,
    required ReceiveMessage receiveMessage,
    required SendMessage sendMessage,
    required SyncHistory syncHistory,
    required PeerRepository peerRepo,
    required IdentityRepository identityRepo,
    required MessageSigner signer,
  })  : _transportManager = transportManager,
        _receiveMessage = receiveMessage,
        _sendMessage = sendMessage,
        _syncHistory = syncHistory,
        _peerRepo = peerRepo,
        _identityRepo = identityRepo,
        _signer = signer;

  final TransportManager _transportManager;
  final ReceiveMessage _receiveMessage;
  final SendMessage _sendMessage;
  final SyncHistory _syncHistory;
  final PeerRepository _peerRepo;
  final IdentityRepository _identityRepo;
  final MessageSigner _signer;

  StreamSubscription<TransportPayload>? _dataSub;
  StreamSubscription<PeerEvent>? _peerSub;

  final StreamController<DecryptedMessage> _decryptedCtrl =
      StreamController<DecryptedMessage>.broadcast();

  /// Stream of successfully decrypted messages for UI consumption.
  Stream<DecryptedMessage> get decryptedMessages => _decryptedCtrl.stream;

  /// Start listening to transport streams. Call after TransportManager.start().
  Future<void> start() async {
    _dataSub = _transportManager.incomingData.listen(_handleIncoming);
    _peerSub = _transportManager.peerEvents.listen(_handlePeerEvent);
  }

  Future<void> stop() async {
    await _dataSub?.cancel();
    await _peerSub?.cancel();
    _dataSub = null;
    _peerSub = null;
  }

  // ── Outgoing ─────────────────────────────────────────────────────────────

  /// Send a text message to a specific peer. Returns the signed, encrypted
  /// envelope (already persisted locally by SendMessage).
  Future<LocalMeshMessage> sendText({
    required String recipientId,
    required String plaintext,
  }) async {
    final msg = await _sendMessage(
      recipientId: recipientId,
      plaintext: plaintext,
    );
    final wire = WireCodec.encode(msg);
    await _transportManager.broadcast(wire);
    return msg;
  }

  // ── Incoming ─────────────────────────────────────────────────────────────

  Future<void> _handleIncoming(TransportPayload payload) async {
    LocalMeshMessage msg;
    try {
      msg = WireCodec.decode(payload.data);
    } catch (e) {
      debugPrint('MessageController: failed to decode payload — $e');
      return;
    }

    // Sync protocol messages bypass the normal router path
    if (msg.type == MessageType.syncRequest) {
      await _handleSyncRequest(msg, payload.fromPeerId);
      return;
    }
    if (msg.type == MessageType.syncResponse) {
      // Sync responses are sent as individual re-transmitted messages —
      // the syncResponse envelope itself carries no content.
      return;
    }
    if (msg.type == MessageType.peerAnnounce) {
      await _handlePeerAnnounce(msg);
      // Announces also flow through router for potential forwarding
    }

    final result = await _receiveMessage(msg);

    // Only surface TEXT messages to the UI; control-plane messages
    // (PEER_ANNOUNCE, sync, etc.) are handled above and must not reach the stream.
    if (result.decrypted != null && msg.type == MessageType.text) {
      _decryptedCtrl.add(result.decrypted!);
    }

    // Forward if the router decided so
    if (result.decision.action == RouterAction.forwardOnly ||
        result.decision.action == RouterAction.deliverAndForward) {
      final forwarded = result.decision.forwardMessage!;
      final wire = WireCodec.encode(forwarded);
      for (final peer in _transportManager.connectedPeers) {
        if (peer == payload.fromPeerId) continue;
        try {
          await _transportManager.sendTo(peer, wire);
        } catch (_) {
          // best-effort
        }
      }
    }
  }

  // ── Peer events ───────────────────────────────────────────────────────────

  Future<void> _handlePeerEvent(PeerEvent event) async {
    await _peerRepo.updatePeerConnectionStatus(event.peerId, event.connected);

    if (event.connected) {
      await _sendPeerAnnounceTo(event.peerId);
      await _sendSyncRequestTo(event.peerId);
    }
  }

  // ── Peer announce ─────────────────────────────────────────────────────────

  Future<void> _sendPeerAnnounceTo(String peerId) async {
    final me = await _identityRepo.getIdentity();
    if (me == null) return;

    // Payload: [sigPub(32)][encPub(32)][displayName UTF-8]
    final nameBytes = utf8.encode(me.displayName);
    final buf = BytesBuilder();
    buf.add(me.signingPublicKey);
    buf.add(me.encryptionPublicKey);
    buf.add(nameBytes);

    var msg = LocalMeshMessage(
      id: 'announce-${me.fingerprint}-${DateTime.now().microsecondsSinceEpoch}',
      version: 1,
      type: MessageType.peerAnnounce,
      senderId: me.fingerprint,
      recipientId: '*',
      payload: buf.toBytes(),
      hopCount: 0,
      ttl: 2,
      lamportTs: DateTime.now().millisecondsSinceEpoch,
      signature: const [],
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    final sig = await _signer.sign(
      message: msg,
      signingPrivateKey: me.signingPrivateKey,
      signingPublicKey: me.signingPublicKey,
    );
    msg = msg.copyWith(signature: sig);

    try {
      await _transportManager.sendTo(peerId, WireCodec.encode(msg));
    } catch (_) {}
  }

  Future<void> _handlePeerAnnounce(LocalMeshMessage msg) async {
    if (msg.payload.length < 64) return;
    try {
      final sigPub = List<int>.from(msg.payload.sublist(0, 32));
      final encPub = List<int>.from(msg.payload.sublist(32, 64));
      final name = utf8.decode(msg.payload.sublist(64));

      final peer = Peer(
        id: msg.senderId,
        displayName: name,
        signingPublicKey: sigPub,
        encryptionPublicKey: encPub,
        lastSeen: DateTime.now().millisecondsSinceEpoch,
        isConnected: true,
        isTrusted: true, // TOFU — trust on first use
      );
      await _peerRepo.savePeer(peer);
    } catch (e) {
      debugPrint('MessageController: bad PEER_ANNOUNCE — $e');
    }
  }

  // ── Sync protocol ─────────────────────────────────────────────────────────

  Future<void> _sendSyncRequestTo(String peerId) async {
    final me = await _identityRepo.getIdentity();
    if (me == null) return;

    final peers = await _peerRepo.getAllPeers();
    // Include own fingerprint — messages addressed to me are stored under my ID
    final chatRoomIds = [...peers.map((p) => p.id), me.fingerprint];
    final request = await _syncHistory.buildRequest(chatRoomIds);

    final jsonPayload =
        Uint8List.fromList(utf8.encode(jsonEncode(request.chatRoomTimestamps)));

    var msg = LocalMeshMessage(
      id: 'sync-req-${me.fingerprint}-${DateTime.now().microsecondsSinceEpoch}',
      version: 1,
      type: MessageType.syncRequest,
      senderId: me.fingerprint,
      recipientId: peerId,
      payload: jsonPayload,
      hopCount: 0,
      ttl: 1, // sync is peer-to-peer only
      lamportTs: DateTime.now().millisecondsSinceEpoch,
      signature: const [],
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    final sig = await _signer.sign(
      message: msg,
      signingPrivateKey: me.signingPrivateKey,
      signingPublicKey: me.signingPublicKey,
    );
    msg = msg.copyWith(signature: sig);

    try {
      await _transportManager.sendTo(peerId, WireCodec.encode(msg));
    } catch (_) {}
  }

  Future<void> _handleSyncRequest(
    LocalMeshMessage msg,
    String fromPeerId,
  ) async {
    try {
      final decoded =
          jsonDecode(utf8.decode(msg.payload)) as Map<String, dynamic>;
      final timestamps = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      final request = SyncRequest(chatRoomTimestamps: timestamps);
      final response = await _syncHistory.respondTo(request);

      for (final m in response.messages) {
        try {
          await _transportManager.sendTo(fromPeerId, WireCodec.encode(m));
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('MessageController: bad SYNC_REQUEST — $e');
    }
  }

  Future<void> dispose() async {
    await stop();
    await _decryptedCtrl.close();
  }
}
