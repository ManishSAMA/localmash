import '../entities/message.dart';
import '../repositories/message_repository.dart';

class SyncRequest {
  SyncRequest({required this.chatRoomTimestamps});
  // roomId -> highest known lamportTs
  final Map<String, int> chatRoomTimestamps;
}

class SyncResponse {
  SyncResponse({required this.messages});
  final List<LocalMeshMessage> messages;
}

class SyncHistory {
  SyncHistory({required MessageRepository messageRepo})
      : _messageRepo = messageRepo;

  final MessageRepository _messageRepo;

  /// Builds a SyncRequest listing the highest known Lamport timestamp
  /// for each chat room. Send this to a reconnecting peer.
  Future<SyncRequest> buildRequest(List<String> chatRoomIds) async {
    final timestamps = <String, int>{};
    for (final roomId in chatRoomIds) {
      timestamps[roomId] =
          await _messageRepo.getHighestLamportTsForChat(roomId);
    }
    return SyncRequest(chatRoomTimestamps: timestamps);
  }

  /// Responds to a sync request by returning all locally-known messages
  /// newer than the requested timestamps.
  Future<SyncResponse> respondTo(SyncRequest request) async {
    final allMessages = <LocalMeshMessage>[];
    for (final entry in request.chatRoomTimestamps.entries) {
      final newer = await _messageRepo.getMessagesForChat(
        entry.key,
        afterLamportTs: entry.value,
        limit: 50,
      );
      allMessages.addAll(newer);
    }
    return SyncResponse(messages: allMessages);
  }
}
