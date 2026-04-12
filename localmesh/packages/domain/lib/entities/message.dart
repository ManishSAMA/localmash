import 'package:meta/meta.dart';

enum MessageType {
  text,
  fileChunk,
  location,
  syncRequest,
  syncResponse,
  peerAnnounce,
}

@immutable
class LocalMeshMessage {
  const LocalMeshMessage({
    required this.id,
    this.version = 1,
    required this.type,
    required this.senderId,
    required this.recipientId,
    required this.payload,
    this.hopCount = 0,
    this.ttl = 5,
    required this.lamportTs,
    required this.signature,
    required this.createdAt,
  });

  final String id;
  final int version;
  final MessageType type;
  final String senderId;
  final String recipientId;
  final List<int> payload;
  final int hopCount;
  final int ttl;
  final int lamportTs;
  final List<int> signature;
  final int createdAt;

  LocalMeshMessage copyWith({int? hopCount}) {
    return LocalMeshMessage(
      id: id,
      version: version,
      type: type,
      senderId: senderId,
      recipientId: recipientId,
      payload: payload,
      hopCount: hopCount ?? this.hopCount,
      ttl: ttl,
      lamportTs: lamportTs,
      signature: signature,
      createdAt: createdAt,
    );
  }
}
