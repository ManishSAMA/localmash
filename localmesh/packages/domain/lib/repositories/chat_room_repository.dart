import '../entities/chat_room.dart';

abstract class ChatRoomRepository {
  Future<void> saveChatRoom(ChatRoom room);
  Future<ChatRoom?> getChatRoomById(String id);
  Future<List<ChatRoom>> getAllChatRooms();
  Future<void> updateLastMessageTs(String id, int ts);
  Future<void> deleteChatRoom(String id);
}
