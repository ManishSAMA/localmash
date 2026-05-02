import 'dart:convert';
import '../entities/message.dart';
import '../protocols/lamport_clock.dart';
import '../protocols/mesh_router.dart';
import '../repositories/identity_repository.dart';
import '../repositories/message_repository.dart';
import '../repositories/peer_repository.dart';
import '../services/message_encryptor.dart';
import '../services/session_key_deriver.dart';

class DecryptedMessage {
  DecryptedMessage({required this.envelope, required this.plaintext});
  final LocalMeshMessage envelope;
  final String plaintext;
}

class ReceiveMessageResult {
  ReceiveMessageResult({required this.decision, this.decrypted});
  final RouterDecision decision;
  final DecryptedMessage? decrypted;
}

class ReceiveMessage {
  ReceiveMessage({
    required MeshRouter router,
    required IdentityRepository identityRepo,
    required PeerRepository peerRepo,
    required MessageRepository messageRepo,
    required MessageEncryptor encryptor,
    required SessionKeyDeriver keyDeriver,
    required LamportClock clock,
  })  : _router = router,
        _identityRepo = identityRepo,
        _peerRepo = peerRepo,
        _messageRepo = messageRepo,
        _encryptor = encryptor,
        _keyDeriver = keyDeriver,
        _clock = clock;

  static const _persistableTypes = contentBearingMessageTypes;

  final MeshRouter _router;
  final IdentityRepository _identityRepo;
  final PeerRepository _peerRepo;
  final MessageRepository _messageRepo;
  final MessageEncryptor _encryptor;
  final SessionKeyDeriver _keyDeriver;
  final LamportClock _clock;

  /// Processes an incoming message:
  ///   1. Ask the router for a decision (dedup, verify, deliver/forward)
  ///   2. If delivered, merge Lamport clock, decrypt, persist
  ///   3. Return the decision so the transport layer can forward if needed
  Future<ReceiveMessageResult> call(LocalMeshMessage message) async {
    final decision = await _router.handleIncoming(message);

    final shouldDeliverLocally =
        decision.action == RouterAction.deliverOnly ||
            decision.action == RouterAction.deliverAndForward;

    if (!shouldDeliverLocally) {
      return ReceiveMessageResult(decision: decision);
    }

    // Merge Lamport clock with the message's timestamp
    _clock.merge(message.lamportTs);

    // Persist only content-bearing messages — control-plane messages
    // (PEER_ANNOUNCE, SYNC_REQUEST) must not appear in the chat history.
    if (_persistableTypes.contains(message.type)) {
      await _messageRepo.saveMessage(message);
    }

    // Attempt to decrypt. Only content-bearing messages reach here
    // (control messages are filtered above), but broadcast messages
    // might not be decryptable by us — that is fine.
    DecryptedMessage? decrypted;
    try {
      final me = await _identityRepo.getIdentity();
      if (me == null) {
        return ReceiveMessageResult(decision: decision);
      }

      final sender = await _peerRepo.getPeerById(message.senderId);
      if (sender == null) {
        return ReceiveMessageResult(decision: decision);
      }

      final sessionKey = await _keyDeriver.deriveSessionKey(
        myPrivateKey: me.encryptionPrivateKey,
        theirPublicKey: sender.encryptionPublicKey,
        myFingerprint: me.fingerprint,
        theirFingerprint: sender.id,
      );

      final plaintextBytes = await _encryptor.decrypt(
        encrypted: message.payload,
        sessionKey: sessionKey,
      );

      decrypted = DecryptedMessage(
        envelope: message,
        plaintext: utf8.decode(plaintextBytes),
      );
    } catch (_) {
      // Decryption failed — envelope is still persisted. UI can show
      // "encrypted message, unable to decrypt" if needed.
      decrypted = null;
    }

    return ReceiveMessageResult(decision: decision, decrypted: decrypted);
  }
}
