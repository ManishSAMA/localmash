import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:domain/domain.dart';
import 'package:transport/transport_package.dart';

class RoutingEvent {
  const RoutingEvent({
    required this.timestamp,
    required this.payload,
    required this.status,
  });

  final DateTime timestamp;
  final String payload;
  final String status;
}

enum PeerHandshakeState {
  discovered,
  connecting,
  announced,
  keyExchangeStarted,
  keyExchangeConfirmed,
  sessionEstablished,
  trustPending,
  verified,
  failed,
}

class MeshLink {
  const MeshLink({
    required this.fromId,
    required this.toId,
    required this.active,
    required this.relay,
    required this.lastSeen,
  });

  final String fromId;
  final String toId;
  final bool active;
  final bool relay;
  final DateTime lastSeen;

  String get key {
    final ids = [fromId, toId]..sort();
    return '${ids[0]}:${ids[1]}';
  }
}

class MeshTopologySnapshot {
  const MeshTopologySnapshot({
    required this.localId,
    required this.localName,
    required this.nodes,
    required this.links,
  });

  final String localId;
  final String localName;
  final Map<String, String> nodes;
  final List<MeshLink> links;
}

class MeshDiagnostics {
  const MeshDiagnostics({
    this.maxHopDepth = 0,
    this.forwardedMessages = 0,
    this.routingEvents = const [],
  });

  final int maxHopDepth;
  final int forwardedMessages;
  final List<RoutingEvent> routingEvents;

  MeshDiagnostics copyWith({
    int? maxHopDepth,
    int? forwardedMessages,
    List<RoutingEvent>? routingEvents,
  }) {
    return MeshDiagnostics(
      maxHopDepth: maxHopDepth ?? this.maxHopDepth,
      forwardedMessages: forwardedMessages ?? this.forwardedMessages,
      routingEvents: routingEvents ?? this.routingEvents,
    );
  }
}

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
    required MessageRepository messageRepo,
    required PeerRepository peerRepo,
    required IdentityRepository identityRepo,
    required MessageSigner signer,
    required IdentityGenerator identityGenerator,
    required MessageEncryptor encryptor,
    required SessionKeyDeriver keyDeriver,
  }) : _transportManager = transportManager,
       _receiveMessage = receiveMessage,
       _sendMessage = sendMessage,
       _syncHistory = syncHistory,
       _messageRepo = messageRepo,
       _peerRepo = peerRepo,
       _identityRepo = identityRepo,
       _signer = signer,
       _identityGenerator = identityGenerator,
       _encryptor = encryptor,
       _keyDeriver = keyDeriver;

  final TransportManager _transportManager;
  final ReceiveMessage _receiveMessage;
  final SendMessage _sendMessage;
  final SyncHistory _syncHistory;
  final MessageRepository _messageRepo;
  final PeerRepository _peerRepo;
  final IdentityRepository _identityRepo;
  final MessageSigner _signer;
  final IdentityGenerator _identityGenerator;
  final MessageEncryptor _encryptor;
  final SessionKeyDeriver _keyDeriver;

  StreamSubscription<TransportPayload>? _dataSub;
  StreamSubscription<PeerEvent>? _peerSub;
  bool _started = false;

  final StreamController<DecryptedMessage> _decryptedCtrl =
      StreamController<DecryptedMessage>.broadcast();
  final StreamController<int> _peerRevisionCtrl =
      StreamController<int>.broadcast();
  final StreamController<int> _messageRevisionCtrl =
      StreamController<int>.broadcast();
  final StreamController<MeshDiagnostics> _diagnosticsCtrl =
      StreamController<MeshDiagnostics>.broadcast();
  final Map<String, String> _plaintextCache = {};
  final Map<String, String> _transportPeerToIdentity = {};
  final Map<String, String> _identityToTransportPeer = {};
  final Set<String> _pendingConnectedTransportPeers = <String>{};
  final Map<String, PeerHandshakeState> _handshakeStates = {};
  final Map<String, int> _handshakeAttempts = {};
  final Map<String, Timer> _handshakeTimers = {};
  final Map<String, MeshLink> _topologyLinks = {};
  final StreamController<Map<String, PeerHandshakeState>> _handshakeCtrl =
      StreamController<Map<String, PeerHandshakeState>>.broadcast();
  final StreamController<MeshTopologySnapshot> _topologyCtrl =
      StreamController<MeshTopologySnapshot>.broadcast();
  int _peerRevision = 0;
  int _messageRevision = 0;
  MeshDiagnostics _diagnostics = const MeshDiagnostics();

  static const int _kPlaintextCacheMax = 1000;
  static const int _kMaxHandshakeRetries = 2;
  static const Duration _kHandshakeTimeout = Duration(seconds: 10);
  static const Duration _kSendTimeout = Duration(seconds: 12);

  /// Stream of successfully decrypted messages for UI consumption.
  Stream<DecryptedMessage> get decryptedMessages => _decryptedCtrl.stream;
  Stream<int> get peerRevisions => _peerRevisionCtrl.stream;
  Stream<int> get messageRevisions => _messageRevisionCtrl.stream;
  Stream<MeshDiagnostics> get diagnostics async* {
    yield _diagnostics;
    yield* _diagnosticsCtrl.stream;
  }

  Stream<Map<String, PeerHandshakeState>> get handshakeStates async* {
    yield Map.unmodifiable(_handshakeStates);
    yield* _handshakeCtrl.stream;
  }

  Stream<MeshTopologySnapshot> get topology async* {
    yield await _buildTopologySnapshot();
    yield* _topologyCtrl.stream;
  }

  String? cachedPlaintextFor(String messageId) => _plaintextCache[messageId];

  Future<String?> decryptForDisplay(LocalMeshMessage msg) async {
    if (!contentBearingMessageTypes.contains(msg.type)) return null;

    if (msg.plaintext != null) {
      _cachePlaintext(msg.id, msg.plaintext!);
      return msg.plaintext;
    }

    final cached = _plaintextCache[msg.id];
    if (cached != null) return cached;

    try {
      final me = await _identityRepo.getIdentity();
      if (me == null) return null;

      final remotePeerId = msg.senderId == me.fingerprint
          ? msg.recipientId
          : msg.senderId;
      final remotePeer = await _peerRepo.getPeerById(remotePeerId);
      if (remotePeer == null) return null;

      final sessionKey = await _keyDeriver.deriveSessionKey(
        myPrivateKey: me.encryptionPrivateKey,
        theirPublicKey: remotePeer.encryptionPublicKey,
        myFingerprint: me.fingerprint,
        theirFingerprint: remotePeer.id,
      );

      final plaintextBytes = await _encryptor.decrypt(
        encrypted: msg.payload,
        sessionKey: sessionKey,
      );
      final plaintext = utf8.decode(plaintextBytes);
      _cachePlaintext(msg.id, plaintext);
      await _messageRepo.updateMessage(msg.copyWith(plaintext: plaintext));
      _emitMessageRevision();
      return plaintext;
    } catch (_) {
      return null;
    }
  }

  /// Start listening to transport streams before TransportManager.start().
  Future<void> start() async {
    if (_started) return;
    debugPrint('[CONTROLLER] starting mesh control-plane listeners');
    // Remove provisional peers left over from a previous session where a clean
    // disconnect event was never received (e.g. crash, self-discovery stall).
    final stale = await _peerRepo.getAllPeers();
    for (final p in stale.where((p) => p.signingPublicKey.isEmpty)) {
      await _peerRepo.removePeer(p.id);
    }
    _dataSub = _transportManager.incomingData.listen(_handleIncoming);
    _peerSub = _transportManager.peerEvents.listen(_handlePeerEvent);
    _started = true;
    debugPrint('[CONTROLLER] mesh control-plane listeners ready');
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
    _cachePlaintext(msg.id, plaintext);
    _emitMessageRevision();
    unawaited(_completeSend(msg));
    return msg;
  }

  Future<void> _completeSend(LocalMeshMessage msg) async {
    final wire = WireCodec.encode(msg);
    var status = MessageDeliveryStatus.delivered;
    try {
      await _ensureTransportReady();
      await _transportManager.broadcast(wire).timeout(_kSendTimeout);
    } catch (e) {
      status = MessageDeliveryStatus.failed;
      debugPrint('[CONTROLLER] send failed for message ${msg.id}: $e');
    }
    final latest = await _messageRepo.getMessageById(msg.id);
    if (latest != null) {
      await _messageRepo.updateMessage(latest.copyWith(deliveryStatus: status));
    }
    _addRoutingEvent(
      payload: status == MessageDeliveryStatus.delivered
          ? 'Text message delivered • ${_shortId(msg.id)}'
          : 'Text message failed • ${_shortId(msg.id)}',
      status: status == MessageDeliveryStatus.delivered ? 'SENT' : 'DROP',
    );
    _emitMessageRevision();
  }

  Future<void> _ensureTransportReady() async {
    if (_transportManager.transports.any(
      (t) => t.state == TransportState.running && t.connectedPeers.isNotEmpty,
    )) {
      return;
    }
    if (_transportManager.transports.any(
      (t) => t.state == TransportState.idle || t.state == TransportState.error,
    )) {
      await _transportManager.start();
    }
  }

  // ── Incoming ─────────────────────────────────────────────────────────────

  Future<void> _handleIncoming(TransportPayload payload) async {
    LocalMeshMessage msg;
    try {
      msg = WireCodec.decode(payload.data);
    } catch (e) {
      debugPrint('MessageController: failed to decode payload — $e');
      _addRoutingEvent(payload: 'Decode failed', status: 'DROP');
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
    if (msg.type == MessageType.keyExchangeStart) {
      await _handleKeyExchangeStart(msg, payload.fromPeerId);
      return;
    }
    if (msg.type == MessageType.keyExchangeConfirm) {
      await _handleKeyExchangeConfirm(msg, payload.fromPeerId);
      return;
    }

    final result = await _receiveMessage(msg);

    // Only surface TEXT messages to the UI; control-plane messages
    // (PEER_ANNOUNCE, sync, etc.) are handled above and must not reach the stream.
    final deliveredLocally =
        result.decision.action == RouterAction.deliverOnly ||
        result.decision.action == RouterAction.deliverAndForward;
    if (deliveredLocally && msg.type == MessageType.text) {
      if (result.decrypted != null) {
        _cachePlaintext(msg.id, result.decrypted!.plaintext);
        _decryptedCtrl.add(result.decrypted!);
      }
      _addRoutingEvent(
        payload: 'Message delivered • ${_shortId(msg.id)}',
        status: 'OK',
      );
      _emitMessageRevision();
    }

    // Forward if the router decided so
    if (result.decision.action == RouterAction.forwardOnly ||
        result.decision.action == RouterAction.deliverAndForward) {
      final forwarded = result.decision.forwardMessage!;
      final wire = WireCodec.encode(forwarded);
      var sent = 0;
      for (final peer in _transportManager.connectedPeers) {
        if (peer == payload.fromPeerId) continue;
        try {
          await _transportManager.sendTo(peer, wire);
          sent++;
          unawaited(_recordRelayLink(payload.fromPeerId, peer));
        } catch (e) {
          debugPrint(
            '[CONTROLLER] forward to $peer failed for message ${forwarded.id}: $e',
          );
          _addRoutingEvent(
            payload: 'Forward failed • ${_shortId(forwarded.id)}',
            status: 'DROP',
          );
        }
      }
      if (sent > 0) {
        _diagnostics = _diagnostics.copyWith(
          maxHopDepth: forwarded.hopCount > _diagnostics.maxHopDepth
              ? forwarded.hopCount
              : _diagnostics.maxHopDepth,
          forwardedMessages: _diagnostics.forwardedMessages + sent,
        );
        _addRoutingEvent(
          payload: 'Gossip forwarded • ${_shortId(forwarded.id)}',
          status: 'OK',
        );
      }
    }
  }

  // ── Peer events ───────────────────────────────────────────────────────────

  Future<void> _handlePeerEvent(PeerEvent event) async {
    debugPrint(
      '[CONTROLLER] transport peer event ${event.connected ? "connected" : "disconnected"} '
      'transport=${event.transportName} id=${event.peerId} name="${event.displayName ?? ''}"',
    );
    final resolvedPeerId =
        _transportPeerToIdentity[event.peerId] ?? event.peerId;
    await _peerRepo.updatePeerConnectionStatus(resolvedPeerId, event.connected);

    if (event.connected) {
      _pendingConnectedTransportPeers.add(event.peerId);
      _setHandshakeState(event.peerId, PeerHandshakeState.connecting);

      // Create provisional peer so UI shows it immediately in Nearby section,
      // even before PEER_ANNOUNCE exchange completes.
      if (!_transportPeerToIdentity.containsKey(event.peerId)) {
        final existing = await _peerRepo.getPeerById(event.peerId);
        if (existing == null) {
          final label = _resolvedDeviceLabel(
            rawName: event.displayName,
            stableId: event.peerId,
          );
          final provisional = Peer(
            id: event.peerId,
            displayName: label,
            signingPublicKey: const [],
            encryptionPublicKey: const [],
            lastSeen: DateTime.now().millisecondsSinceEpoch,
            isConnected: true,
            isTrusted: false,
          );
          await _peerRepo.savePeer(provisional);
          debugPrint(
            '[CONTROLLER] provisional peer created transportId=${event.peerId} label="$label"',
          );
        }
      }
    } else {
      _pendingConnectedTransportPeers.remove(event.peerId);
      final identityPeerId = _transportPeerToIdentity.remove(event.peerId);
      if (identityPeerId != null) {
        _identityToTransportPeer.remove(identityPeerId);
        await _peerRepo.updatePeerConnectionStatus(identityPeerId, false);
        _handshakeTimers.remove(identityPeerId)?.cancel();
        _setHandshakeState(identityPeerId, PeerHandshakeState.discovered);
        _removeActiveLink(identityPeerId);
      }
      _handshakeTimers.remove(event.peerId)?.cancel();
      // Clean up stale provisional peer on disconnect
      final provisional = await _peerRepo.getPeerById(event.peerId);
      if (provisional != null && provisional.signingPublicKey.isEmpty) {
        await _peerRepo.removePeer(event.peerId);
      }
    }

    _addRoutingEvent(
      payload:
          'Peer ${event.connected ? "connected" : "disconnected"} • ${_shortId(event.peerId)}',
      status: event.connected ? 'OK' : 'DISC',
    );
    _emitPeerRevision();

    if (event.connected) {
      debugPrint(
        '[CONTROLLER] sending announce to transport peer ${event.peerId}',
      );
      await _sendPeerAnnounceTo(event.peerId);
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

    final payload = jsonEncode({
      'v': 2,
      'sig': base64Encode(me.signingPublicKey),
      'enc': base64Encode(me.encryptionPublicKey),
      'name': _validIdentityName(me.displayName, me.fingerprint),
    });

    var msg = LocalMeshMessage(
      id: 'announce-${me.fingerprint}-${DateTime.now().microsecondsSinceEpoch}',
      version: 1,
      type: MessageType.peerAnnounce,
      senderId: me.fingerprint,
      recipientId: '*',
      payload: Uint8List.fromList(utf8.encode(payload)),
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
      _addRoutingEvent(
        payload: 'Peer announce sent • ${_shortId(peerId)}',
        status: 'OK',
      );
      debugPrint('[CONTROLLER] peer announce sent to $peerId');
    } catch (e) {
      debugPrint('[CONTROLLER] peer announce failed for $peerId: $e');
    }
  }

  Future<void> _handlePeerAnnounce(
    LocalMeshMessage msg,
    String transportPeerId,
  ) async {
    try {
      debugPrint(
        '[CONTROLLER] peer announce received sender=${msg.senderId} transport=$transportPeerId',
      );
      final parsed = _parseAnnouncePayload(msg.payload);
      if (parsed == null) return;
      final sigPub = parsed.signingPublicKey;
      final encPub = parsed.encryptionPublicKey;
      final name = _validPeerName(
        announcedName: parsed.displayName,
        transportName: null,
        stableId: msg.senderId,
      );
      final computedFingerprint = await _identityGenerator.computeFingerprint(
        sigPub,
      );
      if (computedFingerprint != msg.senderId) {
        debugPrint(
          'MessageController: rejecting PEER_ANNOUNCE with mismatched fingerprint',
        );
        return;
      }

      // Self-discovery: our own GATT advertisement reflected back by BLE scan.
      final me = await _identityRepo.getIdentity();
      if (me != null && computedFingerprint == me.fingerprint) {
        debugPrint(
          '[CONTROLLER] self-announce detected for $transportPeerId — discarding',
        );
        _pendingConnectedTransportPeers.remove(transportPeerId);
        final provisional = await _peerRepo.getPeerById(transportPeerId);
        if (provisional != null && provisional.signingPublicKey.isEmpty) {
          await _peerRepo.removePeer(transportPeerId);
        }
        _emitPeerRevision();
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
      debugPrint(
        '[CONTROLLER] transport peer mapped transport=$transportPeerId identity=${msg.senderId}',
      );
      if (_pendingConnectedTransportPeers.contains(transportPeerId)) {
        await _peerRepo.updatePeerConnectionStatus(msg.senderId, true);
      }
      unawaited(_recordActiveLink(msg.senderId));
      _setHandshakeState(msg.senderId, PeerHandshakeState.announced);
      _emitPeerRevision();
      _addRoutingEvent(
        payload: 'Peer announce received • ${_shortId(msg.senderId)}',
        status: 'OK',
      );
      await _maybeStartDeterministicHandshake(msg.senderId);
    } catch (e) {
      debugPrint('MessageController: bad PEER_ANNOUNCE — $e');
    }
  }

  Future<void> _maybeStartDeterministicHandshake(String peerId) async {
    final me = await _identityRepo.getIdentity();
    if (me == null) return;
    final peer = await _peerRepo.getPeerById(peerId);
    if (peer == null || peer.signingPublicKey.isEmpty) return;
    if (peer.isTrusted) {
      _setHandshakeState(peerId, PeerHandshakeState.verified);
      return;
    }
    if (me.fingerprint.compareTo(peerId) < 0) {
      debugPrint(
        '[CONTROLLER] deterministic key exchange owner; starting with $peerId',
      );
      await _sendKeyExchangeStart(peerId);
    }
  }

  Future<void> _sendKeyExchangeStart(String peerId) async {
    final attempts = _handshakeAttempts[peerId] ?? 0;
    if (attempts > _kMaxHandshakeRetries) {
      await _failHandshake(peerId);
      return;
    }
    _handshakeAttempts[peerId] = attempts + 1;
    _setHandshakeState(peerId, PeerHandshakeState.keyExchangeStarted);
    debugPrint(
      '[CONTROLLER] key exchange start peer=$peerId attempt=${attempts + 1}',
    );
    try {
      await _sendControl(peerId, MessageType.keyExchangeStart);
    } catch (e) {
      debugPrint('[CONTROLLER] key exchange start failed for $peerId: $e');
    }
    _armHandshakeTimeout(peerId, () => _sendKeyExchangeStart(peerId));
  }

  Future<void> _handleKeyExchangeStart(
    LocalMeshMessage msg,
    String transportPeerId,
  ) async {
    final me = await _identityRepo.getIdentity();
    if (me == null) return;
    final peer = await _peerRepo.getPeerById(msg.senderId);
    if (peer == null || peer.signingPublicKey.isEmpty) return;
    if (!await _verifyControlMessage(msg, peer)) return;
    if (me.fingerprint.compareTo(msg.senderId) < 0) {
      return;
    }
    _transportPeerToIdentity[transportPeerId] = msg.senderId;
    _identityToTransportPeer[msg.senderId] = transportPeerId;
    _setHandshakeState(msg.senderId, PeerHandshakeState.keyExchangeStarted);
    debugPrint('[CONTROLLER] key exchange start received from ${msg.senderId}');
    await _sendControl(msg.senderId, MessageType.keyExchangeConfirm);
    await _establishSession(msg.senderId);
  }

  Future<void> _handleKeyExchangeConfirm(
    LocalMeshMessage msg,
    String transportPeerId,
  ) async {
    final peer = await _peerRepo.getPeerById(msg.senderId);
    if (peer == null || peer.signingPublicKey.isEmpty) return;
    if (!await _verifyControlMessage(msg, peer)) return;
    _transportPeerToIdentity[transportPeerId] = msg.senderId;
    _identityToTransportPeer[msg.senderId] = transportPeerId;
    _setHandshakeState(msg.senderId, PeerHandshakeState.keyExchangeConfirmed);
    debugPrint('[CONTROLLER] key exchange confirmed by ${msg.senderId}');
    await _establishSession(msg.senderId);
  }

  Future<bool> _verifyControlMessage(LocalMeshMessage msg, Peer peer) async {
    return _signer.verify(
      message: msg,
      signingPublicKey: peer.signingPublicKey,
    );
  }

  Future<void> _establishSession(String peerId) async {
    _handshakeTimers.remove(peerId)?.cancel();
    _setHandshakeState(peerId, PeerHandshakeState.sessionEstablished);
    debugPrint('[CONTROLLER] session established with $peerId');
    final peer = await _peerRepo.getPeerById(peerId);
    _setHandshakeState(
      peerId,
      peer?.isTrusted == true
          ? PeerHandshakeState.verified
          : PeerHandshakeState.trustPending,
    );
    await _peerRepo.updatePeerConnectionStatus(peerId, true);
    final transportPeerId = _identityToTransportPeer[peerId];
    if (transportPeerId != null) await _sendSyncRequestTo(transportPeerId);
    _emitPeerRevision();
    debugPrint('[CONTROLLER] UI peer state updated for $peerId');
  }

  Future<void> _sendControl(String peerId, MessageType type) async {
    final me = await _identityRepo.getIdentity();
    if (me == null) return;
    final transportPeerId = _identityToTransportPeer[peerId] ?? peerId;
    var msg = LocalMeshMessage(
      id: '${type.name}-${me.fingerprint}-${DateTime.now().microsecondsSinceEpoch}',
      version: 1,
      type: type,
      senderId: me.fingerprint,
      recipientId: peerId,
      payload: Uint8List(0),
      hopCount: 0,
      ttl: 1,
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
    await _transportManager.sendTo(transportPeerId, WireCodec.encode(msg));
  }

  void _armHandshakeTimeout(String peerId, Future<void> Function() retry) {
    _handshakeTimers.remove(peerId)?.cancel();
    _handshakeTimers[peerId] = Timer(_kHandshakeTimeout, () async {
      if (_handshakeStates[peerId] == PeerHandshakeState.trustPending ||
          _handshakeStates[peerId] == PeerHandshakeState.verified) {
        return;
      }
      final attempts = _handshakeAttempts[peerId] ?? 0;
      if (attempts <= _kMaxHandshakeRetries) {
        await retry();
      } else {
        await _failHandshake(peerId);
      }
    });
  }

  Future<void> _failHandshake(String peerId) async {
    _handshakeTimers.remove(peerId)?.cancel();
    _setHandshakeState(peerId, PeerHandshakeState.failed);
    await _peerRepo.updatePeerConnectionStatus(peerId, false);
    _emitPeerRevision();
  }

  // ── Sync protocol ─────────────────────────────────────────────────────────

  Future<void> _sendSyncRequestTo(String peerId) async {
    final me = await _identityRepo.getIdentity();
    if (me == null) return;

    final peers = await _peerRepo.getAllPeers();
    // Include own fingerprint — messages addressed to me are stored under my ID
    final chatRoomIds = [...peers.map((p) => p.id), me.fingerprint];
    final request = await _syncHistory.buildRequest(chatRoomIds);

    final jsonPayload = Uint8List.fromList(
      utf8.encode(jsonEncode(request.chatRoomTimestamps)),
    );

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
      _addRoutingEvent(
        payload: 'Sync request sent • ${_shortId(peerId)}',
        status: 'SYNC',
      );
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
          _transportManager
              .sendTo(fromPeerId, WireCodec.encode(m))
              .then((_) {
                debugPrint(
                  '[CONTROLLER] sync response message ${m.id} sent to $fromPeerId',
                );
              })
              .catchError((Object e) {
                debugPrint(
                  '[CONTROLLER] sync response message ${m.id} failed for $fromPeerId: $e',
                );
              }),
      ]);
    } catch (e) {
      debugPrint('MessageController: bad SYNC_REQUEST — $e');
    }
  }

  void _cachePlaintext(String messageId, String plaintext) {
    if (_plaintextCache.length >= _kPlaintextCacheMax) {
      _plaintextCache.remove(_plaintextCache.keys.first);
    }
    _plaintextCache[messageId] = plaintext;
  }

  Future<void> dispose() async {
    await stop();
    await _decryptedCtrl.close();
    await _peerRevisionCtrl.close();
    await _messageRevisionCtrl.close();
    await _diagnosticsCtrl.close();
    await _handshakeCtrl.close();
    await _topologyCtrl.close();
  }

  Future<void> trustPeer(String peerId) async {
    await _peerRepo.trustPeer(peerId);
    _setHandshakeState(peerId, PeerHandshakeState.verified);
    _emitPeerRevision();
    debugPrint('[CONTROLLER] peer trusted $peerId; UI peer state updated');
  }

  void _emitPeerRevision() {
    _peerRevision++;
    _peerRevisionCtrl.add(_peerRevision);
  }

  void _emitMessageRevision() {
    _messageRevision++;
    _messageRevisionCtrl.add(_messageRevision);
  }

  void _addRoutingEvent({required String payload, required String status}) {
    final next = [
      RoutingEvent(timestamp: DateTime.now(), payload: payload, status: status),
      ..._diagnostics.routingEvents,
    ].take(50).toList(growable: false);
    _diagnostics = _diagnostics.copyWith(routingEvents: next);
    _diagnosticsCtrl.add(_diagnostics);
  }

  String _shortId(String id) => id.length <= 12 ? id : id.substring(0, 12);

  void _setHandshakeState(String peerId, PeerHandshakeState state) {
    _handshakeStates[peerId] = state;
    _handshakeCtrl.add(Map.unmodifiable(_handshakeStates));
  }

  Future<void> _recordActiveLink(String peerId) async {
    final me = await _identityRepo.getIdentity();
    if (me == null) return;
    final link = MeshLink(
      fromId: me.fingerprint,
      toId: peerId,
      active: true,
      relay: false,
      lastSeen: DateTime.now(),
    );
    _topologyLinks[link.key] = link;
    _topologyCtrl.add(await _buildTopologySnapshot());
  }

  Future<void> _recordRelayLink(
    String fromTransportId,
    String toTransportId,
  ) async {
    final from = _transportPeerToIdentity[fromTransportId] ?? fromTransportId;
    final to = _transportPeerToIdentity[toTransportId] ?? toTransportId;
    if (from == to) return;
    final link = MeshLink(
      fromId: from,
      toId: to,
      active: false,
      relay: true,
      lastSeen: DateTime.now(),
    );
    _topologyLinks[link.key] = link;
    _topologyCtrl.add(await _buildTopologySnapshot());
  }

  void _removeActiveLink(String peerId) {
    _topologyLinks.removeWhere(
      (_, link) =>
          link.active && (link.fromId == peerId || link.toId == peerId),
    );
    unawaited(_buildTopologySnapshot().then(_topologyCtrl.add));
  }

  Future<MeshTopologySnapshot> _buildTopologySnapshot() async {
    final me = await _identityRepo.getIdentity();
    final localId = me?.fingerprint ?? 'local';
    final nodes = <String, String>{
      localId: me == null
          ? 'This node'
          : _validIdentityName(me.displayName, localId),
    };
    for (final peer in await _peerRepo.getAllPeers()) {
      if (peer.signingPublicKey.isEmpty &&
          _handshakeStates[peer.id] != PeerHandshakeState.failed) {
        continue;
      }
      nodes[peer.id] = _validPeerName(
        announcedName: peer.displayName,
        transportName: null,
        stableId: peer.id,
      );
    }
    for (final link in _topologyLinks.values) {
      nodes.putIfAbsent(link.fromId, () => _fallbackNodeName(link.fromId));
      nodes.putIfAbsent(link.toId, () => _fallbackNodeName(link.toId));
    }
    return MeshTopologySnapshot(
      localId: localId,
      localName: nodes[localId]!,
      nodes: Map.unmodifiable(nodes),
      links: List.unmodifiable(_topologyLinks.values),
    );
  }

  _AnnouncePayload? _parseAnnouncePayload(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final sig = base64Decode(json['sig'] as String);
      final enc = base64Decode(json['enc'] as String);
      if (sig.length != 32 || enc.length != 32) return null;
      return _AnnouncePayload(
        signingPublicKey: sig,
        encryptionPublicKey: enc,
        displayName: json['name'] as String?,
      );
    } catch (_) {
      if (payload.length < 64) return null;
      return _AnnouncePayload(
        signingPublicKey: List<int>.from(payload.sublist(0, 32)),
        encryptionPublicKey: List<int>.from(payload.sublist(32, 64)),
        displayName: utf8.decode(payload.sublist(64), allowMalformed: true),
      );
    }
  }

  String _validIdentityName(String name, String stableId) {
    final cleaned = name.trim();
    if (_isBadName(cleaned)) return _fallbackNodeName(stableId);
    return cleaned;
  }

  String _validPeerName({
    required String? announcedName,
    required String? transportName,
    required String stableId,
  }) {
    for (final candidate in [announcedName, transportName]) {
      final cleaned = candidate?.trim() ?? '';
      if (!_isBadName(cleaned)) return cleaned;
    }
    return _fallbackNodeName(stableId);
  }

  String _resolvedDeviceLabel({
    required String? rawName,
    required String stableId,
  }) {
    return _validPeerName(
      announcedName: null,
      transportName: rawName,
      stableId: stableId,
    );
  }

  bool _isBadName(String name) {
    if (name.isEmpty) return true;
    final normalized = name.toLowerCase();
    return normalized == 'localmesh' ||
        normalized == 'unknown' ||
        normalized == 'null';
  }

  String _fallbackNodeName(String stableId) {
    final cleaned = stableId.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final suffixSource = cleaned.isNotEmpty ? cleaned : stableId;
    final suffix = suffixSource.length <= 4
        ? suffixSource
        : suffixSource.substring(suffixSource.length - 4);
    return 'Node-${suffix.toUpperCase()}';
  }
}

class _AnnouncePayload {
  const _AnnouncePayload({
    required this.signingPublicKey,
    required this.encryptionPublicKey,
    required this.displayName,
  });

  final List<int> signingPublicKey;
  final List<int> encryptionPublicKey;
  final String? displayName;
}
