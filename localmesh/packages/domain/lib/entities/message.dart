import 'package:meta/meta.dart';

enum MessageType {
  text,
  fileChunk,
  location,
  syncRequest,
  syncResponse,
  peerAnnounce,
}

/// The set of [MessageType] values that carry user-visible content.
/// Used to decide whether a message should be persisted and whether
/// it can be decrypted for display.
const contentBearingMessageTypes = {
  MessageType.text,
  MessageType.fileChunk,
  MessageType.location,
};

@immutable
class LocalMeshMessage {
  const LocalMeshMessage({
    required this.id,
    required this.version,
    required this.type,
    required this.senderId,
    required this.recipientId,
    required this.payload,
    required this.hopCount,
    required this.ttl,
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

  bool get isBroadcast => recipientId == '*';
  bool get canForward => hopCount < ttl;

  LocalMeshMessage copyWith({
    String? id,
    int? version,
    MessageType? type,
    String? senderId,
    String? recipientId,
    List<int>? payload,
    int? hopCount,
    int? ttl,
    int? lamportTs,
    List<int>? signature,
    int? createdAt,
  }) {
    return LocalMeshMessage(
      id: id ?? this.id,
      version: version ?? this.version,
      type: type ?? this.type,
      senderId: senderId ?? this.senderId,
      recipientId: recipientId ?? this.recipientId,
      payload: payload ?? this.payload,
      hopCount: hopCount ?? this.hopCount,
      ttl: ttl ?? this.ttl,
      lamportTs: lamportTs ?? this.lamportTs,
      signature: signature ?? this.signature,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalMeshMessage && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'LocalMeshMessage(id: $id, type: $type, from: $senderId, '
      'to: $recipientId, hop: $hopCount/$ttl, ts: $lamportTs)';
}
