import '../entities/message.dart';

abstract class MessageRepository {
  Future<void> saveMessage(LocalMeshMessage message);
  Future<List<LocalMeshMessage>> getMessages(String chatRoomId, {int? afterLamportTs});
  Future<LocalMeshMessage?> getMessageById(String id);
  Future<bool> hasMessage(String id);
}
