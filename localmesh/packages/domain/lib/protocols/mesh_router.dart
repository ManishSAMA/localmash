import 'dart:collection';
import '../entities/message.dart';
import '../services/message_signer.dart';

/// The decision returned by the MeshRouter after examining an incoming message.
enum RouterAction {
  /// Drop silently — duplicate, invalid signature, or TTL exhausted.
  drop,

  /// Deliver to this node's application layer (this node is the recipient
  /// or the message is a broadcast), but do NOT forward further.
  deliverOnly,

  /// Forward to other peers but do NOT deliver locally (not for us).
  forwardOnly,

  /// Deliver locally AND forward to other peers.
  deliverAndForward,
}

class RouterDecision {
  const RouterDecision({
    required this.action,
    this.forwardMessage,
    required this.reason,
  });

  final RouterAction action;
  final LocalMeshMessage? forwardMessage;
  final String reason;
}

/// Implements the LocalMesh gossip routing algorithm:
///
///   1. Dedup by message ID (LRU-bounded set)
///   2. Verify signature against sender's public key
///   3. Determine delivery (is this for me or a broadcast?)
///   4. Determine forwarding (hopCount < ttl?)
///
/// The router is a pure decision engine — it does NOT perform network I/O.
/// It does NOT call transports directly. It returns a RouterDecision and
/// the calling code (a use case) is responsible for acting on it.
class MeshRouter {
  MeshRouter({
    required MessageSigner signer,
    required String myFingerprint,
    required Future<List<int>?> Function(String senderId) lookupSenderPublicKey,
    int maxSeenMessages = 10000,
  })  : _signer = signer,
        _myFingerprint = myFingerprint,
        _lookupSenderPublicKey = lookupSenderPublicKey,
        _maxSeenMessages = maxSeenMessages,
        _seenMessages = LinkedHashSet<String>();

  final MessageSigner _signer;
  final String _myFingerprint;
  final int _maxSeenMessages;
  final LinkedHashSet<String> _seenMessages;

  // Lookup function: given a senderId fingerprint, return the peer's
  // signing public key. Returns null if the peer is unknown.
  final Future<List<int>?> Function(String senderId) _lookupSenderPublicKey;

  /// Returns true if this message has been seen before.
  bool hasSeen(String messageId) => _seenMessages.contains(messageId);

  /// Marks a message as seen. Enforces the LRU cap — oldest entries are
  /// evicted first when the set exceeds _maxSeenMessages.
  void markSeen(String messageId) {
    _seenMessages.add(messageId);
    while (_seenMessages.length > _maxSeenMessages) {
      _seenMessages.remove(_seenMessages.first);
    }
  }

  /// Number of messages currently in the dedup set. For testing/metrics.
  int get seenCount => _seenMessages.length;

  /// Examines an incoming message and decides what to do with it.
  /// This is the main entry point called by the ReceiveMessage use case.
  Future<RouterDecision> handleIncoming(LocalMeshMessage message) async {
    // 1. Dedup check
    if (hasSeen(message.id)) {
      return const RouterDecision(action: RouterAction.drop, reason: 'duplicate');
    }

    // 2. Ignore messages we sent ourselves (shouldn't happen but defend
    //    against transport echo)
    if (message.senderId == _myFingerprint) {
      markSeen(message.id);
      return const RouterDecision(action: RouterAction.drop, reason: 'self-origin');
    }

    // 3. Signature verification
    final senderPublicKey = await _lookupSenderPublicKey(message.senderId);
    if (senderPublicKey == null) {
      // Unknown sender — drop until application layer has accepted the peer.
      // PEER_ANNOUNCE handling is special-cased in the ReceiveMessage use case.
      return const RouterDecision(
          action: RouterAction.drop, reason: 'unknown-sender');
    }

    final signatureValid = await _signer.verify(
      message: message,
      signingPublicKey: senderPublicKey,
    );
    if (!signatureValid) {
      // Do NOT markSeen — don't pollute the dedup set with attacker-supplied
      // IDs that never validate.
      return const RouterDecision(
          action: RouterAction.drop, reason: 'invalid-signature');
    }

    // 4. Mark as seen (after validation passes)
    markSeen(message.id);

    // 5. Determine delivery and forwarding
    final isForMe = message.recipientId == _myFingerprint;
    final isBroadcast = message.isBroadcast;
    final canForward = message.canForward;

    final shouldDeliver = isForMe || isBroadcast;

    if (shouldDeliver && canForward) {
      final forwarded = message.copyWith(hopCount: message.hopCount + 1);
      return RouterDecision(
        action: RouterAction.deliverAndForward,
        forwardMessage: forwarded,
        reason: 'deliver-and-forward',
      );
    } else if (shouldDeliver) {
      return const RouterDecision(
          action: RouterAction.deliverOnly, reason: 'deliver-ttl-exhausted');
    } else if (canForward) {
      final forwarded = message.copyWith(hopCount: message.hopCount + 1);
      return RouterDecision(
        action: RouterAction.forwardOnly,
        forwardMessage: forwarded,
        reason: 'forward-only',
      );
    } else {
      return const RouterDecision(
          action: RouterAction.drop, reason: 'not-for-me-and-ttl-exhausted');
    }
  }

  /// Clears the seen set. For testing only.
  void reset() {
    _seenMessages.clear();
  }
}
