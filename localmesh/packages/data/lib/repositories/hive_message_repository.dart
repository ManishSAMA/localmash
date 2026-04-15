import 'package:domain/domain.dart';
import '../datasources/hive_local_datasource.dart';

class HiveMessageRepository implements MessageRepository {
  @override
  Future<void> saveMessage(LocalMeshMessage message) async {
    await HiveLocalDataSource.messagesBox.put(message.id, message);
  }

  @override
  Future<List<LocalMeshMessage>> getMessagesForChat(
    String chatRoomId, {
    int? afterLamportTs,
    int limit = 100,
  }) async {
    var messages = HiveLocalDataSource.messagesBox.values
        .where(
          (m) => m.senderId == chatRoomId || m.recipientId == chatRoomId,
        )
        .toList();

    if (afterLamportTs != null) {
      messages = messages.where((m) => m.lamportTs > afterLamportTs).toList();
    }

    messages.sort((a, b) => a.lamportTs.compareTo(b.lamportTs));

    if (messages.length > limit) {
      messages = messages.sublist(messages.length - limit);
    }

    return messages;
  }

  @override
  Future<LocalMeshMessage?> getMessageById(String id) async {
    return HiveLocalDataSource.messagesBox.get(id);
  }

  @override
  Future<bool> hasMessage(String id) async {
    return HiveLocalDataSource.messagesBox.containsKey(id);
  }

  @override
  Future<int> getHighestLamportTsForChat(String chatRoomId) async {
    final messages = HiveLocalDataSource.messagesBox.values
        .where(
          (m) => m.senderId == chatRoomId || m.recipientId == chatRoomId,
        )
        .toList();

    if (messages.isEmpty) return 0;
    return messages.map((m) => m.lamportTs).reduce((a, b) => a > b ? a : b);
  }

  @override
  Future<void> deleteMessage(String id) async {
    await HiveLocalDataSource.messagesBox.delete(id);
  }
}
