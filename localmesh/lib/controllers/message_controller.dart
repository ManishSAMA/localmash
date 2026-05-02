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
    required IdentityGenerator identityGenerator,
  })  : _transportManager = transportManager,
        _receiveMessage = receiveMessage,
        _sendMessage = sendMessage,
        _syncHistory = syncHistory,
        _peerRepo = peerRepo,
        _identityRepo = identityRepo,
        _signer = signer,
        _identityGenerator = identityGenerator;

  final TransportManager _transportManager;
  final ReceiveMessage _receiveMessage;
  final SendMessage _sendMessage;
  final SyncHistory _syncHistory;
  final PeerRepository _peerRepo;
  final IdentityRepository _identityRepo;
  final MessageSigner _signer;
  final IdentityGenerator _identityGenerator;

  StreamSubscription<TransportPayload>? _dataSub;
  StreamSubscription<PeerEvent>? _peerSub;
  bool _started = false;

  final StreamController<DecryptedMessage> _decryptedCtrl =
      StreamController<DecryptedMessage>.broadcast();
  final StreamController<int> _peerRevisionCtrl =
      StreamController<int>.broadcast();
  final StreamController<int> _messageRevisionCtrl =
      StreamController<int>.broadcast();
  final Map<String, String> _plaintextCache = {};
  final Map<String, String> _transportPeerToIdentity = {};
  final Map<String, String> _identityToTransportPeer = {};
  final Set<String> _pendingConnectedTransportPeers = <String>{};
  int _peerRevision = 0;
  int _messageRevision = 0;

  /// Stream of successfully decrypted messages for UI consumption.
  Stream<DecryptedMessage> get decryptedMessages => _decryptedCtrl.stream;
  Stream<int> get peerRevisions => _peerRevisionCtrl.stream;
  Stream<int> get messageRevisions => _messageRevisionCtrl.stream;

  String? cachedPlaintextFor(String messageId) => _plaintextCache[messageId];

  /// Start listening to transport streams. Call after TransportManager.start().
  Future<void> start() async {
    if (_started) return;
    _dataSub = _transportManager.incomingData.listen(_handleIncoming);
    _peerSub = _transportManager.peerEvents.listen(_handlePeerEvent);
    _started = true;
  }

  Future<void> stop() async {
    await _dataSub?.cancel();
    await _peerSub?.cancel();
    _dataSub = null;
    _peerSub = null;
    _started = false;
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
    _plaintextCache[msg.id] = plaintext;
    final wire = WireCodec.encode(msg);
    await _transportManager.broadcast(wire);
    _emitMessageRevision();
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
      await _handlePeerAnnounce(msg, payload.fromPeerId);
      // Announces also flow through router for potential forwarding
    }

    final result = await _receiveMessage(msg);

    // Only surface TEXT messages to the UI; control-plane messages
    // (PEER_ANNOUNCE, sync, etc.) are handled above and must not reach the stream.
    final deliveredLocally =
        result.decision.action == RouterAction.deliverOnly ||
            result.decision.action == RouterAction.deliverAndForward;
    if (deliveredLocally && msg.type == MessageType.text) {
      if (result.decrypted != null) {
        _plaintextCache[msg.id] = result.decrypted!.plaintext;
        _decryptedCtrl.add(result.decrypted!);
      }
      _emitMessageRevision();
    }

    // Forward if the router decided so
    if (result.decision.action == RouterAction.forwardOnly ||
        result.decision.action == RouterAction.deliverAndForward) {
      final forwarded = result.decision.forwardMessage!;
      final wire = WireCodec.encode(forwarded);
      await Future.wait([
        for (final peer in _transportManager.connectedPeers)
          if (peer != payload.fromPeerId)
            _transportManager.sendTo(peer, wire).catchError((Object e) {
              debugPrint(
                '[CONTROLLER] forward to $peer failed for message ${forwarded.id}: $e',
              );
            }),
      ]);
    }
  }

  // ── Peer events ───────────────────────────────────────────────────────────

  Future<void> _handlePeerEvent(PeerEvent event) async {
    final resolvedPeerId = _transportPeerToIdentity[event.peerId] ?? event.peerId;
    await _peerRepo.updatePeerConnectionStatus(resolvedPeerId, event.connected);

    if (event.connected) {
      _pendingConnectedTransportPeers.add(event.peerId);

      // Create provisional peer so UI shows it immediately in Nearby section,
      // even before PEER_ANNOUNCE exchange completes.
      if (!_transportPeerToIdentity.containsKey(event.peerId)) {
        final existing = await _peerRepo.getPeerById(event.peerId);
        if (existing == null) {
          final provisional = Peer(
            id: event.peerId,
            displayName: (event.displayName?.isNotEmpty == true)
                ? event.displayName!
                : 'Nearby Device',
            signingPublicKey: const [],
            encryptionPublicKey: const [],
            lastSeen: DateTime.now().millisecondsSinceEpoch,
            isConnected: true,
            isTrusted: false,
          );
          await _peerRepo.savePeer(provisional);
        }
      }
    } else {
      _pendingConnectedTransportPeers.remove(event.peerId);
      final identityPeerId = _transportPeerToIdentity.remove(event.peerId);
      if (identityPeerId != null) {
        _identityToTransportPeer.remove(identityPeerId);
        await _peerRepo.updatePeerConnectionStatus(identityPeerId, false);
      }
      // Clean up stale provisional peer on disconnect
      final provisional = await _peerRepo.getPeerById(event.peerId);
      if (provisional != null && provisional.signingPublicKey.isEmpty) {
        await _peerRepo.removePeer(event.peerId);
      }
    }

    _emitPeerRevision();

    if (event.connected) {
      await _sendPeerAnnounceTo(event.peerId);
      await _sendSyncRequestTo(event.peerId);
      // Retry announce after 4 s in case of BLE packet loss
      _scheduleAnnounceRetry(event.peerId);
    }
  }

  void _scheduleAnnounceRetry(String transportPeerId) {
    Future.delayed(const Duration(seconds: 4), () {
      if (_pendingConnectedTransportPeers.contains(transportPeerId) &&
          !_transportPeerToIdentity.containsKey(transportPeerId)) {
        debugPrint('[CONTROLLER] retrying PEER_ANNOUNCE for $transportPeerId');
        _sendPeerAnnounceTo(transportPeerId);
        // One more retry at 10 s
        Future.delayed(const Duration(seconds: 6), () {
          if (_pendingConnectedTransportPeers.contains(transportPeerId) &&
              !_transportPeerToIdentity.containsKey(transportPeerId)) {
            _sendPeerAnnounceTo(transportPeerId);
          }
        });
      }
    });
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
      debugPrint('[CONTROLLER] peer announce sent to $peerId');
    } catch (e) {
      debugPrint('[CONTROLLER] peer announce failed for $peerId: $e');
    }
  }

  Future<void> _handlePeerAnnounce(
    LocalMeshMessage msg,
    String transportPeerId,
  ) async {
    if (msg.payload.length < 64) return;
    try {
      final sigPub = List<int>.from(msg.payload.sublist(0, 32));
      final encPub = List<int>.from(msg.payload.sublist(32, 64));
      final name = utf8.decode(msg.payload.sublist(64));
      final computedFingerprint =
          await _identityGenerator.computeFingerprint(sigPub);
      if (computedFingerprint != msg.senderId) {
        debugPrint(
          'MessageController: rejecting PEER_ANNOUNCE with mismatched fingerprint',
        );
        return;
      }

      final existingPeer = await _peerRepo.getPeerById(msg.senderId);
      if (existingPeer != null &&
          existingPeer.signingPublicKey.isNotEmpty &&
          (!listEquals(existingPeer.signingPublicKey, sigPub) ||
              !listEquals(existingPeer.encryptionPublicKey, encPub))) {
        debugPrint(
          'MessageController: rejecting PEER_ANNOUNCE that changes trusted keys for ${msg.senderId}',
        );
        return;
      }

      // Remove provisional peer (keyed by transport ID) if identity differs
      if (transportPeerId != msg.senderId) {
        final provisional = await _peerRepo.getPeerById(transportPeerId);
        if (provisional != null && provisional.signingPublicKey.isEmpty) {
          await _peerRepo.removePeer(transportPeerId);
        }
      }

      // Preserve trust state across reconnects; new peers start untrusted
      final isTrusted = existingPeer?.isTrusted ?? false;

      final peer = Peer(
        id: msg.senderId,
        displayName: name,
        signingPublicKey: sigPub,
        encryptionPublicKey: encPub,
        lastSeen: DateTime.now().millisecondsSinceEpoch,
        isConnected: _pendingConnectedTransportPeers.contains(transportPeerId),
        isTrusted: isTrusted,
      );
      await _peerRepo.savePeer(peer);
      _transportPeerToIdentity[transportPeerId] = msg.senderId;
      _identityToTransportPeer[msg.senderId] = transportPeerId;
      if (_pendingConnectedTransportPeers.contains(transportPeerId)) {
        await _peerRepo.updatePeerConnectionStatus(msg.senderId, true);
      }
      _emitPeerRevision();
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
      debugPrint('[CONTROLLER] sync request sent to $peerId');
    } catch (e) {
      debugPrint('[CONTROLLER] sync request failed for $peerId: $e');
    }
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

      await Future.wait([
        for (final m in response.messages)
          _transportManager.sendTo(fromPeerId, WireCodec.encode(m)).then((_) {
            debugPrint(
              '[CONTROLLER] sync response message ${m.id} sent to $fromPeerId',
            );
          }).catchError((Object e) {
            debugPrint(
              '[CONTROLLER] sync response message ${m.id} failed for $fromPeerId: $e',
            );
          }),
      ]);
    } catch (e) {
      debugPrint('MessageController: bad SYNC_REQUEST — $e');
    }
  }

  Future<void> dispose() async {
    await stop();
    await _decryptedCtrl.close();
    await _peerRevisionCtrl.close();
    await _messageRevisionCtrl.close();
  }

  Future<void> trustPeer(String peerId) async {
    await _peerRepo.trustPeer(peerId);
    _emitPeerRevision();
  }

  void _emitPeerRevision() {
    _peerRevision++;
    _peerRevisionCtrl.add(_peerRevision);
  }

  void _emitMessageRevision() {
    _messageRevision++;
    _messageRevisionCtrl.add(_messageRevision);
  }
}
