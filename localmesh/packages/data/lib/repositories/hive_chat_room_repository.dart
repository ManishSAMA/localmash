import 'package:domain/domain.dart';
import '../datasources/hive_local_datasource.dart';

class HiveChatRoomRepository implements ChatRoomRepository {
  @override
  Future<void> saveChatRoom(ChatRoom room) async {
    await HiveLocalDataSource.chatRoomsBox.put(room.id, room);
  }

  @override
  Future<ChatRoom?> getChatRoomById(String id) async {
    return HiveLocalDataSource.chatRoomsBox.get(id);
  }

  @override
  Future<List<ChatRoom>> getAllChatRooms() async {
    return HiveLocalDataSource.chatRoomsBox.values.toList();
  }

  @override
  Future<void> updateLastMessageTs(String id, int ts) async {
    final room = HiveLocalDataSource.chatRoomsBox.get(id);
    if (room != null) {
      await saveChatRoom(room.copyWith(lastMessageTs: ts));
    }
  }

  @override
  Future<void> deleteChatRoom(String id) async {
    await HiveLocalDataSource.chatRoomsBox.delete(id);
  }
}
