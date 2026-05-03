import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../entities/message.dart';
import '../protocols/lamport_clock.dart';
import '../repositories/identity_repository.dart';
import '../repositories/message_repository.dart';
import '../repositories/peer_repository.dart';
import '../services/message_encryptor.dart';
import '../services/message_signer.dart';
import '../services/session_key_deriver.dart';

class SendMessage {
  SendMessage({
    required IdentityRepository identityRepo,
    required PeerRepository peerRepo,
    required MessageRepository messageRepo,
    required MessageEncryptor encryptor,
    required MessageSigner signer,
    required SessionKeyDeriver keyDeriver,
    required LamportClock clock,
  })  : _identityRepo = identityRepo,
        _peerRepo = peerRepo,
        _messageRepo = messageRepo,
        _encryptor = encryptor,
        _signer = signer,
        _keyDeriver = keyDeriver,
        _clock = clock,
        _uuid = const Uuid();

  final IdentityRepository _identityRepo;
  final PeerRepository _peerRepo;
  final MessageRepository _messageRepo;
  final MessageEncryptor _encryptor;
  final MessageSigner _signer;
  final SessionKeyDeriver _keyDeriver;
  final LamportClock _clock;
  final Uuid _uuid;

  /// Builds a fully signed, encrypted, ready-to-transmit LocalMeshMessage.
  /// Persists it locally before returning so offline-first invariants hold.
  /// The caller (UI or controller) is responsible for handing the result
  /// to the transport layer.
  Future<LocalMeshMessage> call({
    required String recipientId,
    required String plaintext,
    MessageType type = MessageType.text,
    int ttl = 5,
  }) async {
    final me = await _identityRepo.getIdentity();
    if (me == null) {
      throw StateError('No local identity — call CreateIdentity first.');
    }

    final recipient = await _peerRepo.getPeerById(recipientId);
    if (recipient == null) {
      throw ArgumentError('Unknown peer: $recipientId');
    }

    final sessionKey = await _keyDeriver.deriveSessionKey(
      myPrivateKey: me.encryptionPrivateKey,
      theirPublicKey: recipient.encryptionPublicKey,
      myFingerprint: me.fingerprint,
      theirFingerprint: recipient.id,
    );

    final encryptedPayload = await _encryptor.encrypt(
      plaintext: utf8.encode(plaintext),
      sessionKey: sessionKey,
    );

    final lamportTs = _clock.tick();

    var message = LocalMeshMessage(
      id: _uuid.v4(),
      version: 1,
      type: type,
      senderId: me.fingerprint,
      recipientId: recipientId,
      payload: encryptedPayload,
      hopCount: 0,
      ttl: ttl,
      lamportTs: lamportTs,
      signature: const [],
      createdAt: DateTime.now().millisecondsSinceEpoch,
      deliveryStatus: MessageDeliveryStatus.sending,
      plaintext: plaintext,
    );

    final signature = await _signer.sign(
      message: message,
      signingPrivateKey: me.signingPrivateKey,
      signingPublicKey: me.signingPublicKey,
    );

    message = message.copyWith(signature: signature);

    // Persist locally BEFORE any network transmission — offline-first.
    await _messageRepo.saveMessage(message);

    return message;
  }
}
