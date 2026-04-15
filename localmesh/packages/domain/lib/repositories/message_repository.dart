import '../entities/message.dart';

abstract class MessageRepository {
  Future<void> saveMessage(LocalMeshMessage message);
  Future<List<LocalMeshMessage>> getMessagesForChat(
    String chatRoomId, {
    int? afterLamportTs,
    int limit = 100,
  });
  Future<LocalMeshMessage?> getMessageById(String id);
  Future<bool> hasMessage(String id);
  Future<int> getHighestLamportTsForChat(String chatRoomId);
  Future<void> deleteMessage(String id);
}
